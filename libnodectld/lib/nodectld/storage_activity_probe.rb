# frozen_string_literal: true

require 'digest'
require 'bigdecimal'
require 'io/wait'
require 'json'
require 'securerandom'
require 'socket'
require 'time'
require 'timeout'

module NodeCtld
  # One signed, bounded observation. It grants no authority to change storage.
  class StorageActivityProbe
    class Invalid < StandardError; end

    VERSION = 1
    HANDLE = 5291
    MAX_SECONDS = 120
    MAX_POOLS = 256
    MAX_ZPOOLS = 32
    MAX_OUTPUT_BYTES = 48 * 1024
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
    ZPOOL = /\A[a-zA-Z0-9_.:-]+\z/
    HEX_64 = /\A[0-9a-f]{64}\z/

    def self.run!(command, params, activity: nil, reader: nil, now: -> { Time.now.utc })
      request = Request.new(command, params, now:).validate!
      activity ||= Daemon.instance
      reader ||= OsctldReader.new
      raise Invalid, 'node activity is unavailable' unless activity

      remaining = request.deadline - now.call
      raise Invalid, 'activity probe deadline elapsed' if remaining <= 0

      Timeout.timeout(remaining) do
        new(request, activity, reader, now:).run!
      end
    rescue Timeout::Error
      raise Invalid, 'activity probe deadline elapsed'
    end

    def initialize(request, activity, reader, now:)
      @request = request
      @activity = activity
      @reader = reader
      @now = now
    end

    def run!
      check_deadline!
      before = frozen_catalog!
      first = local_snapshot!
      pools = @request.zpools.to_h do |zpool|
        check_deadline!
        [zpool, @reader.read!(zpool, deadline: @request.deadline)]
      end
      second = local_snapshot!
      after = frozen_catalog!
      raise Invalid, 'freeze or Pool catalog changed during probe' unless before == after

      node_observed = [first, second].all? do |sample|
        sample[:unknown_reasons] == ['child_lifetime_unproved'] && !sample[:overflow]
      end && first[:daemon_boot_uuid] == second[:daemon_boot_uuid] &&
                      first[:effect_generation] == second[:effect_generation]
      result = {
        protocol_version: VERSION, request_uuid: @request.request_uuid,
        attempt_uuid: @request.attempt_uuid, request_digest: @request.digest,
        nonce: @request.nonce, response_nonce: SecureRandom.hex(32),
        node_id: @request.node_id, freeze_epoch: @request.freeze_epoch,
        observed_mode: 'read_only',
        pool_ids: @request.claims.map { |claim| claim.fetch('pool_id') },
        zpools: @request.zpools,
        node_activity: second, osctld: pools,
        node_activity_observed: node_observed,
        node_queues_empty: node_observed && [first, second].all? { |sample| queues_empty?(sample) },
        gc_trash_observed: pools.values.all? { |v| !v.fetch('unknown') && v.fetch('idle') },
        node_quiet: false, repair_ready: false
      }
      raise Invalid, 'activity output exceeds transaction limit' if JSON.generate(result).bytesize > MAX_OUTPUT_BYTES

      result
    end

    private

    def check_deadline!
      raise Invalid, 'activity probe deadline elapsed' if @now.call >= @request.deadline
    end

    def queues_empty?(sample)
      sample[:queues].is_a?(Hash) &&
        sample[:queues].values.all? do |counts|
          counts[:workers] == 0 && counts[:reservations] == 0
        end && sample[:pending_reservations] == 0 &&
        sample[:detached_blockers] == 0 && sample[:tracked_children] == 0
    end

    def frozen_catalog!
      check_deadline!
      Db.open do |db|
        freeze = db.prepared(
          'SELECT mode, epoch FROM storage_freeze_controls WHERE id = 1'
        ).get
        raise Invalid, 'freeze epoch changed or is not read_only' unless
          freeze && freeze['mode'].to_i == 1 &&
          freeze['epoch'].to_i == @request.freeze_epoch

        rows = []
        db.prepared(
          'SELECT id, node_id, filesystem, zpool_guid FROM pools WHERE node_id = ? ' \
          'ORDER BY id LIMIT ?', @request.node_id, MAX_POOLS + 1
        ).each { |row| rows << row }
        raise Invalid, 'node Pool scope differs from signed request' if rows.length > MAX_POOLS

        claims = rows.map do |row|
          root = row.fetch('filesystem')
          {
            'pool_id' => row.fetch('id').to_i,
            'managed_root' => root,
            'zpool' => root.split('/').first,
            'zpool_guid' => Request.decimal(row['zpool_guid'])
          }
        end
        raise Invalid, 'node Pool scope differs from signed request' unless claims == @request.claims

        [freeze.fetch('epoch').to_i, claims]
      end
    end

    def local_snapshot!
      check_deadline!
      sample = @activity.node_activity_snapshot(
        timeout: [0.05, @request.deadline - @now.call].min,
        excluding_transaction_id: @request.transaction_id
      )
      raise Invalid, 'node activity response is unavailable' unless
        sample.is_a?(Hash) && sample[:version] == 1 &&
        sample[:coverage] == 'node_activity_v1' &&
        sample[:daemon_boot_uuid].is_a?(String) &&
        sample[:effect_generation].is_a?(Integer)

      sample
    end

    class Request
      attr_reader :request_uuid, :attempt_uuid, :nonce, :node_id,
                  :freeze_epoch, :deadline, :claims, :digest, :transaction_id

      def self.decimal(value)
        return nil if value.nil?

        raw = case value
              when BigDecimal then value.to_s('F')
              when Integer, String then value.to_s
              else raise Invalid, 'invalid Pool GUID'
              end
        raise Invalid, 'invalid Pool GUID' unless raw.match?(/\A\d+(?:\.0+)?\z/)

        raw.split('.').first
      end

      def initialize(command, params, now:)
        @command = command
        @params = params.transform_keys(&:to_s)
        @now = now
      end

      def validate!
        trans = @command.trans
        input = trans.fetch('input')
        raise Invalid, 'activity probe is unsigned' if trans['signature'].to_s.empty?
        raise Invalid, 'activity probe signature is invalid' unless
          TransactionVerifier.verify_base64(input, trans['signature'])
        raise Invalid, 'wrong activity handle' unless trans['handle'].to_i == HANDLE

        signed = JSON.parse(input)
        raise Invalid, 'activity input differs from signed request' unless
          signed.is_a?(Hash) && signed['handle'] == HANDLE &&
          signed['node'] == trans['node_id'].to_i &&
          signed['transaction_chain'] == trans['transaction_chain_id'].to_i &&
          signed['depends_on'] == trans['depends_on_id'] &&
          signed['input'].is_a?(Hash) &&
          signed['input'] == @params.except('vps_id')
        raise Invalid, 'activity request fields are invalid' unless
          @params.except('vps_id').keys.sort == %w[
            attempt_uuid claims deadline freeze_epoch node_id nonce
            protocol_version request_uuid
          ].sort
        raise Invalid, 'unsupported activity protocol' unless @params['protocol_version'] == VERSION

        @request_uuid = @params.fetch('request_uuid')
        @attempt_uuid = @params.fetch('attempt_uuid')
        @nonce = @params.fetch('nonce')
        raise Invalid, 'invalid activity request identity' unless
          [request_uuid, attempt_uuid].all? { |v| v.is_a?(String) && UUID.match?(v) } &&
          nonce.is_a?(String) && HEX_64.match?(nonce)

        @node_id = Integer(@params.fetch('node_id'))
        @freeze_epoch = Integer(@params.fetch('freeze_epoch'))
        @transaction_id = Integer(trans.fetch('id'))
        raise Invalid, 'wrong activity node' unless node_id == Integer(trans.fetch('node_id')) &&
                                                    node_id == $CFG.get(:vpsadmin, :node_id).to_i
        raise Invalid, 'invalid freeze epoch' if freeze_epoch < 0

        @claims = @params.fetch('claims')
        validate_claims!
        @deadline = Time.iso8601(@params.fetch('deadline'))
        raise Invalid, 'invalid activity deadline' unless
          deadline > @now.call && deadline <= @now.call + MAX_SECONDS

        @digest = Digest::SHA256.hexdigest(input)
        self
      rescue JSON::ParserError, KeyError, ArgumentError, TypeError
        raise Invalid, 'malformed signed activity request'
      end

      def zpools
        claims.map { |claim| claim.fetch('zpool') }.uniq.sort
      end

      private

      def validate_claims!
        raise Invalid, 'invalid activity Pool claims' unless
          claims.is_a?(Array) && claims.length.between?(1, MAX_POOLS)

        ids = []
        roots = []
        claims.each do |claim|
          raise Invalid, 'invalid activity Pool claim' unless
            claim.is_a?(Hash) && claim.keys.sort == %w[managed_root pool_id zpool zpool_guid]

          id = claim.fetch('pool_id')
          root = claim.fetch('managed_root')
          zpool = claim.fetch('zpool')
          guid = claim.fetch('zpool_guid')
          raise Invalid, 'invalid activity Pool claim' unless
            id.is_a?(Integer) && id > 0 && root.is_a?(String) &&
            zpool.is_a?(String) && ZPOOL.match?(zpool) &&
            (root == zpool || root.start_with?("#{zpool}/")) &&
            !root.include?("\0") &&
            (guid.nil? || (guid.is_a?(String) && guid.match?(/\A\d+\z/)))

          ids << id
          roots << root
        end
        raise Invalid, 'duplicate or unordered activity Pool claims' unless
          ids == ids.uniq.sort && roots.uniq.length == roots.length
        raise Invalid, 'too many activity zpools' if zpools.length > MAX_ZPOOLS
      end
    end

    # The generic OsCtl client concatenates unbounded recv chunks. This reader
    # enforces the signed deadline and a byte cap while receiving each line.
    class OsctldReader
      MAX_LINE_BYTES = 4096
      SOCKET = '/run/osctl/osctld.sock'

      def initialize(socket_path: SOCKET)
        @socket_path = socket_path
      end

      def read!(zpool, deadline:)
        socket = Timeout.timeout(remaining(deadline)) { UNIXSocket.new(@socket_path) }
        @buffer = +''
        greeting = receive!(socket, deadline:)
        raise Invalid, 'osctld greeting is invalid' unless greeting.is_a?(Hash) &&
                                                           greeting['version'].is_a?(String)

        request = "#{JSON.generate(cmd: 'pool_storage_activity', opts: { pool: zpool })}\n"
        Timeout.timeout(remaining(deadline)) { socket.write(request) }
        response = receive!(socket, deadline:)
        raise Invalid, 'osctld activity command failed' unless
          response.is_a?(Hash) && response['status'] == true &&
          response.keys.sort == %w[response status]

        validate_response!(response.fetch('response'), zpool)
      rescue Timeout::Error, IOError, SystemCallError
        raise Invalid, 'osctld activity is unavailable'
      ensure
        socket&.close
      end

      private

      def receive!(socket, deadline:)
        loop do
          if (index = @buffer.index("\n"))
            raw = @buffer.slice!(0, index + 1)
            raise Invalid, 'osctld response exceeds byte limit' if raw.bytesize > MAX_LINE_BYTES

            return JSON.parse(raw, max_nesting: 20)
          end
          raise Invalid, 'osctld response exceeds byte limit' if @buffer.bytesize >= MAX_LINE_BYTES
          raise Invalid, 'osctld response timed out' unless socket.wait_readable(remaining(deadline))

          chunk = socket.recv_nonblock([1024, MAX_LINE_BYTES - @buffer.bytesize].min)
          raise Invalid, 'osctld closed an incomplete response' if chunk.nil? || chunk.empty?

          @buffer << chunk
        end
      rescue IO::WaitReadable
        retry
      rescue JSON::ParserError
        raise Invalid, 'osctld response is malformed'
      end

      def remaining(deadline)
        left = deadline - Time.now.utc
        raise Invalid, 'osctld response timed out' if left <= 0

        left
      end

      def validate_response!(value, zpool)
        raise Invalid, 'osctld activity response is invalid' unless value.is_a?(Hash)

        keys = %w[
          version coverage daemon_boot_uuid pool_instance_uuid generation pool
          state counts registered_run_datasets worker_alive unknown_reasons
          unknown overflow idle
        ]
        raise Invalid, 'osctld activity fields are invalid' unless value.keys.sort == keys.sort
        raise Invalid, 'unsupported osctld activity coverage' unless
          value['version'] == 1 && value['coverage'] == 'gc_trash_v1' && value['pool'] == zpool
        raise Invalid, 'osctld activity identity is invalid' unless
          [value['daemon_boot_uuid'], value['pool_instance_uuid']].all? do |uuid|
            uuid.nil? || (uuid.is_a?(String) && UUID.match?(uuid))
          end
        raise Invalid, 'osctld daemon identity is missing' if value['daemon_boot_uuid'].nil?
        raise Invalid, 'osctld active Pool has no instance identity' if
          value['state'] == 'active' && value['pool_instance_uuid'].nil?
        raise Invalid, 'osctld activity generation is invalid' unless
          bounded_count?(value['generation']) &&
          bounded_count?(value['registered_run_datasets'])
        raise Invalid, 'osctld activity state is invalid' unless
          %w[active importing stopping absent].include?(value['state'])

        counts = value['counts']
        raise Invalid, 'osctld activity counts are invalid' unless
          counts.is_a?(Hash) && counts.keys.sort == %w[run_gc trash_move trash_prune] &&
          counts.values.all? do |entry|
            entry.is_a?(Hash) && entry.keys.sort == %w[pending running] &&
            entry.values.all? { |count| bounded_count?(count, max: 10_000) }
          end

        workers = value['worker_alive']
        raise Invalid, 'osctld worker state is invalid' unless
          workers.is_a?(Hash) && workers.keys.sort == %w[run_gc trash_prune] &&
          workers.values.all? { |alive| [true, false].include?(alive) }

        reasons = value['unknown_reasons']
        raise Invalid, 'osctld unknown reasons are invalid' unless
          reasons.is_a?(Array) && reasons.length <= 8 && reasons.uniq == reasons &&
          reasons.all? { |reason| reason.is_a?(String) && reason.bytesize <= 64 }
        raise Invalid, 'osctld activity flags are invalid' unless
          %w[unknown overflow idle].all? { |key| [true, false].include?(value[key]) }
        raise Invalid, 'contradictory osctld known state' if
          !value['unknown'] && (value['overflow'] || value['unknown_reasons'].any? ||
                                value['state'] != 'active' || !workers.values.all?)
        if value['idle'] && (value['unknown'] || value['overflow'] ||
                             value['state'] != 'active' || !workers.values.all? ||
                             !counts.values.all? { |v| v.values.all?(&:zero?) })
          raise Invalid, 'contradictory osctld idle state'
        end

        value
      end

      def bounded_count?(value, max: nil)
        value.is_a?(Integer) && value >= 0 && (!max || value <= max)
      end
    end
  end
end
