# frozen_string_literal: true

require 'digest'
require 'bigdecimal'
require 'fileutils'
require 'securerandom'
require 'time'
require 'timeout'

module VpsAdmin
  module StorageReconciler
    # Private, sampled G1 evidence. No observation here grants repair authority.
    class ActivityReport
      class Incomplete < StandardError; end

      MAX_POOLS = 256
      MAX_ZPOOLS_PER_NODE = 32
      MAX_PROBE_SECONDS = 120
      MAX_REPORT_SECONDS = 4 * 60 * 60
      HEX_64 = /\A[0-9a-f]{64}\z/
      UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
      OSCTLD_FIELDS = %w[
        version coverage daemon_boot_uuid pool_instance_uuid generation pool
        state counts registered_run_datasets worker_alive unknown_reasons
        unknown overflow idle
      ].freeze
      EXPECTED_QUEUES = %w[
        general storage inventory network vps zfs_send zfs_recv mail dns
        outage queue rollback
      ].freeze

      attr_reader :report_directory

      def initialize(private_dir:, status_reader: nil, catalog_reader: nil,
                     probe_runner: nil, capture_runner: nil, signer_unlocker: nil,
                     clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        @private_dir = private_dir
        @status_reader = status_reader || -> { StorageFreezeStatus.snapshot }
        @catalog_reader = catalog_reader || -> { catalog! }
        @probe_runner = probe_runner || method(:probe_node!)
        @capture_runner = capture_runner || method(:capture_pool!)
        @signer_unlocker = signer_unlocker
        @clock = clock
      end

      def run!
        @deadline = @clock.call + MAX_REPORT_SECONDS
        prepare_private_directory!
        @capture_runs = []
        @node_ids = []
        @pool_ids = []
        state = 'unknown'
        reason = nil
        observed = {}
        begin
          within_deadline! do
            before = frozen_status!
            pools = @catalog_reader.call
            validate_catalog!(pools)
            @pool_ids = pools.map { |p| p.fetch(:pool_id) }
            grouped = pools.group_by { |p| p.fetch(:node_id) }.sort.to_h
            @node_ids = grouped.keys
            unlock_signer!(pools.first)

            first = probe_all!(grouped, before.fetch(:epoch))
            pools.each do |pool|
              run_id = @capture_runner.call(pool.fetch(:pool_id), @capture_directory)
              @capture_runs << { pool_id: pool.fetch(:pool_id), run_id: Integer(run_id) }
              remaining_seconds!
            end
            during = frozen_status!
            raise Incomplete, 'freeze changed across inventory' unless
              during.fetch(:epoch) == before.fetch(:epoch)
            raise Incomplete, 'Pool catalog changed across inventory' unless
              @catalog_reader.call == pools

            second = probe_all!(grouped, before.fetch(:epoch))
            after = frozen_status!
            raise Incomplete, 'freeze changed after probes' unless
              after.fetch(:epoch) == before.fetch(:epoch)
            raise Incomplete, 'Pool catalog changed after probes' unless
              @catalog_reader.call == pools

            observed = compare_samples!(first, second, grouped)
            reason = observed.fetch(:reason)
            state = reason == 'child_lifetime_unproved' ? 'sampled_incomplete' : 'unknown'
          end
        rescue Incomplete, StandardError => e
          reason = e.is_a?(Incomplete) ? e.message : 'activity report could not complete'
        end

        report = {
          'version' => 1, 'coverage' => 'g1_advisory_v1', 'state' => state,
          'reason' => reason, 'observed_at' => Time.now.utc.iso8601(6),
          'pool_ids' => @pool_ids, 'node_ids' => @node_ids,
          'capture_runs' => @capture_runs,
          'observations' => observed,
          'node_quiet' => false, 'repair_ready' => false, 'executable' => false
        }
        report = JSON.parse(Format.canonical(report))
        report['digest'] = Format.digest(report)
        write_report!(report)
        report
      end

      private

      def within_deadline!
        Timeout.timeout(remaining_seconds!, Incomplete, 'activity report deadline elapsed') do
          result = yield
          remaining_seconds!
          result
        end
      end

      def remaining_seconds!
        remaining = @deadline - @clock.call
        raise Incomplete, 'activity report deadline elapsed' if remaining <= 0

        remaining
      end

      def catalog!
        pools = Pool.includes(:node).order(:id).limit(MAX_POOLS + 1).to_a
        raise Incomplete, 'Pool catalog exceeds activity bound' if pools.length > MAX_POOLS

        pools.map do |pool|
          root = pool.filesystem
          raise Incomplete, 'Pool managed root is invalid' unless
            root.is_a?(String) && !root.empty? && !root.include?("\0")

          { pool_id: pool.id, node_id: pool.node_id, node_domain: pool.node.domain_name,
            managed_root: root, zpool: root.split('/').first,
            zpool_guid: decimal_guid(pool.zpool_guid) }
        end
      end

      def decimal_guid(value)
        return nil if value.nil?

        raw = case value
              when BigDecimal then value.to_s('F')
              when Integer, String then value.to_s
              else raise Incomplete, 'Pool GUID is invalid'
              end
        raise Incomplete, 'Pool GUID is invalid' unless raw.match?(/\A\d+(?:\.0+)?\z/)

        raw.split('.').first
      end

      def validate_catalog!(pools)
        raise Incomplete, 'Pool catalog is empty or too large' unless
          pools.is_a?(Array) && pools.length.between?(1, MAX_POOLS)

        ids = pools.map { |pool| pool.fetch(:pool_id) }
        raise Incomplete, 'Pool catalog is not unique and ordered' unless ids == ids.uniq.sort

        roots = pools.map { |pool| [pool.fetch(:node_id), pool.fetch(:managed_root)] }
        raise Incomplete, 'Pool roots are ambiguous' unless roots.uniq.length == roots.length

        pools.group_by { |pool| pool.fetch(:node_id) }.each_value do |node_pools|
          zpools = node_pools.map { |pool| pool.fetch(:zpool) }.uniq
          raise Incomplete, 'node zpool set exceeds activity bound' if zpools.length > MAX_ZPOOLS_PER_NODE

          node_pools.each do |pool|
            root = pool.fetch(:managed_root)
            zpool = pool.fetch(:zpool)
            raise Incomplete, 'Pool root differs from zpool claim' unless
              root == zpool || root.start_with?("#{zpool}/")
          end
        end
      end

      def frozen_status!
        status = @status_reader.call
        raise Incomplete, 'storage freeze is not DB-drained at a stable epoch' unless
          status[:mode] == 'read_only' && status[:stable_epoch] && status[:db_drained] &&
          status[:count_capped].all? { |name| StorageFreezeStatus::INFORMATIONAL_COUNT_NAMES.include?(name) } &&
          status[:epoch].is_a?(Integer)

        status
      end

      def unlock_signer!(pool)
        return if VpsAdmin::API::TransactionSigner.unlocked?
        return @signer_unlocker.call if @signer_unlocker

        Capture.new(pool_id: pool.fetch(:pool_id), mode: 'steady',
                    private_dir: @capture_directory).unlock_signer!
      end

      def claims_for(pools)
        pools.sort_by { |pool| pool.fetch(:pool_id) }.map do |pool|
          { 'pool_id' => pool.fetch(:pool_id), 'managed_root' => pool.fetch(:managed_root),
            'zpool' => pool.fetch(:zpool), 'zpool_guid' => pool.fetch(:zpool_guid) }
        end
      end

      def probe_all!(grouped, epoch)
        grouped.to_h do |node_id, pools|
          remaining_seconds!
          request = {
            protocol_version: 1, request_uuid: SecureRandom.uuid,
            attempt_uuid: SecureRandom.uuid, nonce: SecureRandom.hex(32),
            node_id:, freeze_epoch: epoch,
            deadline: (Time.now.utc + MAX_PROBE_SECONDS).iso8601(6),
            claims: claims_for(pools)
          }
          output = @probe_runner.call(node_id, pools.first.fetch(:node_domain), request)
          validate_probe!(output, request)
          [node_id, output]
        end
      end

      def probe_node!(_node_id, _domain, request)
        chain, = TransactionChains::Storage::ActivityProbe.fire(request)
        transaction = chain.transactions.sole
        raise Incomplete, 'activity probe command was not signed' if transaction.signature.to_s.empty?

        digest = Digest::SHA256.hexdigest(transaction.input)
        deadline = Time.iso8601(request.fetch(:deadline))
        loop do
          raise Incomplete, 'activity probe timed out' if Time.now.utc >= deadline

          Timeout.timeout([deadline - Time.now.utc, 5].min) do
            transaction.reload
            chain.reload
          end
          raise Incomplete, 'activity probe failed' if chain.failed? || chain.fatal?

          if transaction.done == 'done'
            raise Incomplete, 'activity probe failed' unless transaction.status.to_i == 1

            output = JSON.parse(transaction.output.to_s).fetch('execute')
            raise Incomplete, 'activity probe failed' unless output.fetch('status') == 'ok'

            return output if output.fetch('request_digest') == digest

            raise Incomplete, 'activity probe request digest differs'
          end
          sleep 0.5
        end
      rescue JSON::ParserError, KeyError
        raise Incomplete, 'activity probe output is incomplete'
      end

      def capture_pool!(pool_id, root)
        capture = Capture.new(pool_id:, mode: 'steady', private_dir: root)
        raise Incomplete, 'two-pass inventory is stale' unless capture.run! == 0

        capture.run.id
      end

      def validate_probe!(output, request)
        raise Incomplete, 'activity probe output is missing' unless output.is_a?(Hash)

        checks = {
          'protocol_version' => 1, 'request_uuid' => request.fetch(:request_uuid),
          'attempt_uuid' => request.fetch(:attempt_uuid), 'nonce' => request.fetch(:nonce),
          'node_id' => request.fetch(:node_id), 'freeze_epoch' => request.fetch(:freeze_epoch),
          'observed_mode' => 'read_only',
          'pool_ids' => request.fetch(:claims).map { |claim| claim.fetch('pool_id') },
          'zpools' => request.fetch(:claims).map { |claim| claim.fetch('zpool') }.uniq.sort,
          'node_quiet' => false, 'repair_ready' => false
        }
        raise Incomplete, 'activity output differs from signed request' unless
          checks.all? { |key, value| output[key] == value } &&
          output['request_digest'].is_a?(String) && HEX_64.match?(output['request_digest']) &&
          output['response_nonce'].is_a?(String) && HEX_64.match?(output['response_nonce'])

        node = output['node_activity']
        raise Incomplete, 'node activity coverage is unavailable' unless
          node.is_a?(Hash) && node['version'] == 1 &&
          node['coverage'] == 'node_activity_v1' &&
          node['daemon_boot_uuid'].is_a?(String) &&
          UUID.match?(node['daemon_boot_uuid']) &&
          bounded_count?(node['effect_generation']) &&
          node['child_coverage'] == 'unknown' && node['unknown'] == true

        queues = node['queues']
        raise Incomplete, 'node queue scope is incomplete' unless
          queues.is_a?(Hash) && queues.keys.sort == EXPECTED_QUEUES.sort &&
          queues.values.all? do |entry|
            entry.is_a?(Hash) && entry.keys.sort == %w[reservations workers] &&
            entry.values.all? { |count| bounded_count?(count, max: 1000) }
          end
        raise Incomplete, 'node activity counters are invalid' unless
          %w[pending_reservations detached_blockers tracked_children].all? do |key|
            bounded_count?(node[key], max: 1000)
          end && [true, false].include?(node['overflow']) &&
          node['unknown_reasons'].is_a?(Array) &&
          node['unknown_reasons'].length <= 16
        raise Incomplete, 'node activity flags are invalid' unless
          [true, false].include?(output['node_activity_observed']) &&
          [true, false].include?(output['node_queues_empty']) &&
          [true, false].include?(output['gc_trash_observed'])
        if output['node_activity_observed'] &&
           (node['unknown_reasons'] != ['child_lifetime_unproved'] || node['overflow'])
          raise Incomplete, 'node activity observed claim is contradictory'
        end
        if output['node_queues_empty'] &&
           (queues.values.any? { |v| v.values.any? { |n| n != 0 } } ||
            %w[pending_reservations detached_blockers tracked_children].any? { |k| node[k] != 0 })
          raise Incomplete, 'node queue empty claim is contradictory'
        end

        osctld = output['osctld']
        zpools = request.fetch(:claims).map { |claim| claim.fetch('zpool') }.uniq.sort
        raise Incomplete, 'osctld scope is incomplete' unless
          osctld.is_a?(Hash) && osctld.keys.sort == zpools

        osctld.each do |zpool, sample|
          raise Incomplete, 'osctld activity coverage is unavailable' unless
            sample.is_a?(Hash) && sample.keys.sort == OSCTLD_FIELDS.sort &&
            sample['pool'] == zpool &&
            sample['version'] == 1 && sample['coverage'] == 'gc_trash_v1' &&
            sample['daemon_boot_uuid'].is_a?(String) &&
            UUID.match?(sample['daemon_boot_uuid']) &&
            (sample['pool_instance_uuid'].nil? ||
             (sample['pool_instance_uuid'].is_a?(String) &&
              UUID.match?(sample['pool_instance_uuid']))) &&
            bounded_count?(sample['generation']) &&
            bounded_count?(sample['registered_run_datasets'], max: 10_000) &&
            %w[active importing stopping absent].include?(sample['state']) &&
            [true, false].include?(sample['unknown']) &&
            [true, false].include?(sample['overflow']) &&
            [true, false].include?(sample['idle'])

          counts = sample['counts']
          raise Incomplete, 'osctld activity counters are invalid' unless
            counts.is_a?(Hash) && counts.keys.sort == %w[run_gc trash_move trash_prune] &&
            counts.values.all? do |entry|
              entry.is_a?(Hash) && entry.keys.sort == %w[pending running] &&
              entry.values.all? { |count| bounded_count?(count, max: 10_000) }
            end

          workers = sample['worker_alive']
          reasons = sample['unknown_reasons']
          raise Incomplete, 'osctld worker or unknown state is invalid' unless
            workers.is_a?(Hash) && workers.keys.sort == %w[run_gc trash_prune] &&
            workers.values.all? { |alive| [true, false].include?(alive) } &&
            reasons.is_a?(Array) && reasons.length <= 8 && reasons.uniq == reasons &&
            reasons.all? { |entry| entry.is_a?(String) && entry.bytesize <= 64 }
          raise Incomplete, 'osctld known state is contradictory' if
            !sample['unknown'] && (sample['overflow'] || reasons.any? ||
                                   sample['state'] != 'active' || !workers.values.all?)
          raise Incomplete, 'osctld idle claim is contradictory' if
            sample['idle'] && (sample['unknown'] || sample['overflow'] ||
                               sample['state'] != 'active' ||
                               sample['pool_instance_uuid'].nil? ||
                               !workers.values.all? ||
                               counts.values.any? { |v| v.values.any? { |count| count != 0 } })
        end
      end

      def bounded_count?(value, max: nil)
        value.is_a?(Integer) && value >= 0 && (!max || value <= max)
      end

      def compare_samples!(first, second, grouped)
        node_observed = true
        queues_empty = true
        gc_observed = true
        stable = true
        evidence = {}
        grouped.each do |node_id, pools|
          previous = first.fetch(node_id)
          current = second.fetch(node_id)
          a = previous.fetch('node_activity')
          b = current.fetch('node_activity')
          node_observed &&= previous['node_activity_observed'] == true &&
                            current['node_activity_observed'] == true
          queues_empty &&= previous['node_queues_empty'] == true &&
                           current['node_queues_empty'] == true
          stable &&= a['daemon_boot_uuid'] == b['daemon_boot_uuid'] &&
                     a['effect_generation'] == b['effect_generation']
          evidence[node_id.to_s] = {
            'node_boot_uuid' => [a['daemon_boot_uuid'], b['daemon_boot_uuid']],
            'node_effect_generation' => [a['effect_generation'], b['effect_generation']],
            'queue_counts' => [a['queues'], b['queues']],
            'child_coverage' => [a['child_coverage'], b['child_coverage']],
            'osctld' => {}
          }
          pools.map { |pool| pool.fetch(:zpool) }.uniq.each do |zpool|
            p = previous.fetch('osctld').fetch(zpool)
            c = current.fetch('osctld').fetch(zpool)
            gc_observed &&= [p, c].all? { |sample| sample['idle'] && !sample['unknown'] }
            stable &&= p['daemon_boot_uuid'] == c['daemon_boot_uuid'] &&
                       p['pool_instance_uuid'] == c['pool_instance_uuid'] &&
                       p['generation'] == c['generation']
            evidence.fetch(node_id.to_s).fetch('osctld')[zpool] = {
              'daemon_boot_uuid' => [p['daemon_boot_uuid'], c['daemon_boot_uuid']],
              'pool_instance_uuid' => [p['pool_instance_uuid'], c['pool_instance_uuid']],
              'generation' => [p['generation'], c['generation']],
              'idle' => [p['idle'], c['idle']],
              'counts' => [p['counts'], c['counts']]
            }
          end
        end
        reason = if !stable
                   'activity_generation_changed'
                 elsif !node_observed
                   'node_activity_unknown'
                 elsif !queues_empty
                   'node_queues_busy'
                 elsif !gc_observed
                   'gc_trash_unknown'
                 else
                   'child_lifetime_unproved'
                 end
        {
          node_activity_observed: node_observed, gc_trash_observed: gc_observed,
          node_queues_empty: queues_empty, generations_stable: stable,
          inventories_complete: true, samples: evidence, reason:,
          node_quiet: false, repair_ready: false
        }
      end

      def prepare_private_directory!
        raise Incomplete, 'private directory must be absolute' unless
          File.absolute_path(@private_dir) == @private_dir

        current = '/'
        @private_dir.split('/').reject(&:empty?).each do |part|
          current = File.join(current, part)
          raise Incomplete, 'private path contains a symlink' if File.symlink?(current)
        end
        stat = File.stat(@private_dir)
        raise Incomplete, 'private directory has unsafe ownership or mode' unless
          stat.directory? && stat.uid == Process.uid && stat.mode & 0o777 == 0o700

        @report_directory = File.join(@private_dir, "activity-#{SecureRandom.uuid}")
        Dir.mkdir(@report_directory, 0o700)
        File.chmod(0o700, @report_directory)
        @capture_directory = File.join(@report_directory, 'captures')
        Dir.mkdir(@capture_directory, 0o700)
        File.chmod(0o700, @capture_directory)
        File.open(@private_dir, File::RDONLY | File::NOFOLLOW, &:fsync)
      end

      def write_report!(report)
        path = File.join(@report_directory, 'report.json')
        encoded = "#{Format.canonical(report)}\n"
        raise Incomplete, 'private activity report exceeds byte limit' if encoded.bytesize > 1024 * 1024

        File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
          file.write(encoded)
          file.flush
          file.fsync
        end
        File.open(@report_directory, File::RDONLY | File::NOFOLLOW, &:fsync)
      end
    end
  end
end
