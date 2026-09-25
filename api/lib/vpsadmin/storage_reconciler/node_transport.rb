require 'bunny'
require 'timeout'

module VpsAdmin
  module StorageReconciler
    class NodeTransport
      class Invalid < StandardError; end

      MAX_FRAME_BYTES = 64 * 1024
      MAX_CHUNK_ROWS = 100
      MAX_CHUNKS = 100_000
      MAX_OBJECTS = 200_000
      PREFETCH = 8
      QUEUE_BYTES = 256 * 1024 * 1024
      QUEUE_LIFETIME_MS = 4 * 60 * 60 * 1000

      attr_reader :queue_name, :routing_key

      def initialize(node_domain:, run_uuid:, attempt_uuid:, node_id:, pool_id:,
                     zpool:, managed_root:, roots:, nonce:, store:, config:)
        @run_uuid = run_uuid
        @attempt_uuid = attempt_uuid
        @node_id = node_id.to_s
        @pool_id = pool_id.to_s
        @zpool = zpool
        @managed_root = managed_root
        @roots = roots
        @nonce = nonce
        @store = store
        @queue_name = "node:#{node_domain}:storage_inventory:#{run_uuid}"
        @routing_key = "storage_inventory:#{run_uuid}"
        @exchange_name = "node:#{node_domain}"
        @config = config
        @inbox = SizedQueue.new(PREFETCH)
        @seen = {}
        @sequence = 0
        @chunk_chain = Digest::SHA256.hexdigest('')
        @row_count = 0
        @last_path = nil
      end

      def open!
        Timeout.timeout(30) do
          @connection = Bunny.new(
            hosts: @config.fetch('hosts'), vhost: @config.fetch('vhost'),
            username: @config.fetch('username'), password: @config.fetch('password'),
            connection_timeout: 15, continuation_timeout: 15_000, log_file: File::NULL
          )
          @connection.start
          @channel = @connection.create_channel
          @channel.prefetch(PREFETCH)
          exchange = @channel.direct(@exchange_name, durable: true)
          @queue = @channel.queue(
            queue_name, durable: true, arguments: {
              'x-queue-type' => 'quorum',
              'x-max-length-bytes' => QUEUE_BYTES,
              'x-overflow' => 'reject-publish',
              'x-expires' => QUEUE_LIFETIME_MS,
              'x-message-ttl' => QUEUE_LIFETIME_MS
            }
          )
          @queue.bind(exchange, routing_key:)
          @queue.subscribe(manual_ack: true, block: false) do |delivery, _metadata, payload|
            @inbox << [delivery.delivery_tag, payload]
          end
        end
        true
      rescue StandardError
        close
        raise
      end

      def receive_until_final!(deadline:, failure_check: nil)
        open_partial!
        loop do
          raise Invalid, 'inventory receive deadline elapsed' if Time.now.utc >= deadline
          raise Invalid, 'node inventory transaction failed' if failure_check&.call

          begin
            delivery, payload = Timeout.timeout([deadline - Time.now.utc, 10].min) do
              @inbox.pop
            end
          rescue Timeout::Error
            raise Invalid, 'inventory transport disconnected' unless @connection&.open?

            next
          end
          frame = parse_frame!(payload)
          if frame['type'] == 'final'
            verify_final!(frame)
            @partial.flush
            @partial.fsync
            @journal.flush
            @journal.fsync
            return [frame, delivery]
          end

          apply_chunk!(frame)
          @channel.ack(delivery)
        end
      end

      def seal!
        @partial.flush
        @partial.fsync
        @partial.close
        @journal.close
        raise Invalid, 'inventory artifact already exists' if File.exist?(@store.path('zfs.jsonl'))

        File.link(partial_path, @store.path('zfs.jsonl'))
        File.unlink(partial_path)
        @store.sync_directory!
      end

      def ack_final!(final_delivery)
        @channel.ack(final_delivery)
      end

      def close
        @partial&.close unless @partial&.closed?
        @journal&.close unless @journal&.closed?
        Timeout.timeout(2) do
          @channel&.close
          @connection&.close
        end
      rescue StandardError
        nil
      end

      private

      def partial_path
        File.join(@store.run_directory, 'zfs.partial')
      end

      def journal_path
        File.join(@store.run_directory, 'zfs-checkpoint.partial')
      end

      def open_partial!
        raise Invalid, 'interrupted inventory attempt requires a new run' if
          File.exist?(partial_path) || File.exist?(journal_path)

        # These descriptors stay open until the ordered stream is sealed or aborted.
        @partial = File.new(
          partial_path, File::RDWR | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600
        )
        @journal = File.new(
          journal_path, File::RDWR | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600
        )
        raise Invalid, 'partial artifact has unsafe permissions' unless
          [@partial, @journal].all? { |f| f.stat.uid == Process.uid && f.stat.mode & 0o077 == 0 }
      end

      def parse_frame!(payload)
        raise Invalid, 'oversize inventory frame' if payload.bytesize > MAX_FRAME_BYTES

        frame = JSON.parse(payload)
        raise Invalid, 'inventory frame is not an object' unless frame.is_a?(Hash)
        raise Invalid, 'inventory frame is not canonically encoded' unless
          payload == Format.canonical(frame)
        raise Invalid, 'unsupported inventory protocol' unless frame['version'] == Format::VERSION
        raise Invalid, 'inventory attempt mismatch' unless
          frame['run_uuid'] == @run_uuid && frame['attempt_uuid'] == @attempt_uuid &&
          frame['node_id'] == @node_id && frame['pool_id'] == @pool_id &&
          frame['zpool'] == @zpool && frame['managed_root'] == @managed_root &&
          frame['roots'] == @roots && frame['nonce'] == @nonce
        raise Invalid, 'inventory frame digest mismatch' unless
          frame['digest'] == Format.digest(frame.except('digest'))

        frame
      rescue JSON::ParserError
        raise Invalid, 'invalid inventory frame JSON'
      end

      def apply_chunk!(frame)
        raise Invalid, 'unexpected inventory frame' unless frame['type'] == 'chunk'

        seq = frame['sequence']
        raise Invalid, 'invalid inventory sequence' unless seq.is_a?(Integer) && seq >= 0

        if seq < @sequence
          raise Invalid, 'conflicting inventory replay' unless @seen.fetch(seq) == frame['digest']

          return
        end
        raise Invalid, 'inventory sequence gap' unless seq == @sequence
        raise Invalid, 'too many inventory chunks' if @sequence >= MAX_CHUNKS

        records = frame['records']
        raise Invalid, 'invalid inventory chunk count' unless
          records.is_a?(Array) && records.length.between?(1, MAX_CHUNK_ROWS) &&
          frame['row_count'] == records.length &&
          frame['records_digest'] == Format.digest(records)
        raise Invalid, 'inventory object limit exceeded' if @row_count + records.length > MAX_OBJECTS

        lines = records.map do |record|
          Format.verify_record!(record, expected_kind: 'zfs_object')
          fields = record.fetch('fields')
          validate_zfs_fields!(fields)
          path = fields.fetch('path')
          raise Invalid, 'inventory is not sorted by path' unless path.is_a?(String) &&
                                                                  (@last_path.nil? || path > @last_path)

          @last_path = path
          "#{Format.canonical(record)}\n"
        end.join
        raise Invalid, 'inventory chunk byte count mismatch' unless
          frame['records_bytes'] == lines.bytesize

        start_offset = @partial.size
        @partial.seek(0, IO::SEEK_END)
        @partial.write(lines)
        @partial.flush
        @partial.fsync

        @chunk_chain = Digest::SHA256.hexdigest(@chunk_chain + frame.fetch('digest'))
        checkpoint = {
          'run_uuid' => @run_uuid, 'attempt_uuid' => @attempt_uuid,
          'sequence' => seq, 'start_offset' => start_offset,
          'end_offset' => start_offset + lines.bytesize,
          'data_digest' => Digest::SHA256.hexdigest(lines),
          'frame_digest' => frame.fetch('digest'),
          'chunk_chain' => @chunk_chain,
          'row_count' => records.length, 'last_path' => @last_path
        }
        @journal.seek(0, IO::SEEK_END)
        @journal.write("#{Format.canonical(checkpoint)}\n")
        @journal.flush
        @journal.fsync
        @seen[seq] = frame['digest']
        @sequence += 1
        @row_count += records.length
      rescue KeyError, Format::Invalid
        raise Invalid, 'invalid inventory chunk'
      end

      def validate_zfs_fields!(fields)
        expected = %w[path type guid owner_path owner_guid origin clones userrefs
                      deferred_destroy creation createtxg]
        raise Invalid, 'inventory object fields are invalid' unless fields.keys.sort == expected.sort

        path = fields.fetch('path')
        raise Invalid, 'inventory path is outside zpool' unless
          path.is_a?(String) && (path == @zpool || path.start_with?("#{@zpool}/", "#{@zpool}@"))
        raise Invalid, 'inventory GUID is invalid' unless decimal_string?(fields['guid'])
        raise Invalid, 'inventory type is invalid' unless %w[filesystem volume snapshot].include?(fields['type'])

        if fields['type'] == 'snapshot'
          raise Invalid, 'snapshot owner identity is invalid' unless
            fields['owner_path'].is_a?(String) && decimal_string?(fields['owner_guid']) &&
            path.start_with?("#{fields['owner_path']}@")
        elsif fields['owner_path'] || fields['owner_guid']
          raise Invalid, 'filesystem cannot have a snapshot owner'
        end
        raise Invalid, 'inventory origin is invalid' unless
          fields['origin'].nil? || fields['origin'].is_a?(String)

        clones = fields['clones']
        raise Invalid, 'inventory clones are invalid' unless
          clones.is_a?(Array) && clones.all?(String) &&
          clones == clones.uniq.sort

        %w[userrefs creation createtxg].each do |key|
          value = fields.fetch(key)
          raise Invalid, 'inventory numeric property is invalid' unless
            decimal_string?(value) || value == { 'unavailable' => true }
        end
        raise Invalid, 'inventory deferred property is invalid' unless
          %w[on off].include?(fields['deferred_destroy']) ||
          fields['deferred_destroy'] == { 'unavailable' => true }
      end

      def decimal_string?(value)
        value.is_a?(String) && value.match?(/\A\d+\z/)
      end

      def verify_final!(frame)
        raise Invalid, 'inventory final sequence mismatch' unless frame['sequence'] == @sequence &&
                                                                  frame['chunk_count'] == @sequence
        raise Invalid, 'inventory final count or chain mismatch' unless
          frame['row_count'] == @row_count && frame['chunk_chain'] == @chunk_chain

        first = frame['first']
        second = frame['second']
        raise Invalid, 'invalid inventory scan summaries' unless first.is_a?(Hash) && second.is_a?(Hash)
        raise Invalid, 'volatile inventory scan' unless
          first['digest'] == second['digest'] && first['count'] == second['count'] &&
          first['zpool_guid'] == second['zpool_guid'] && first['roots'] == second['roots']
        raise Invalid, 'inventory scan count mismatch' unless first['count'] == @row_count

        @partial.flush
        @partial.fsync
        @partial.rewind
        digest = Digest::SHA256.new
        @partial.each_line { |line| digest.update(line) }
        raise Invalid, 'inventory data digest mismatch' unless first['digest'] == digest.hexdigest

        verify_edges!
        raise Invalid, 'invalid root evidence' unless
          first['roots'].is_a?(Hash) && first['roots'].keys.sort == @roots.sort &&
          first['roots'].values.all? { |v| v.to_s.match?(/\A\d+\z/) } &&
          first['zpool_guid'].to_s.match?(/\A\d+\z/)
      end

      def verify_edges!
        objects = {}
        @partial.rewind
        @partial.each_line do |line|
          fields = Format.parse_line!(line, expected_kind: 'zfs_object').fetch('fields')
          path = fields.fetch('path')
          raise Invalid, 'duplicate inventory object' if objects.has_key?(path)

          objects[path] = fields
          raise Invalid, 'inventory object limit exceeded' if objects.size > MAX_OBJECTS
        end
        objects.each do |path, fields|
          if fields['type'] == 'snapshot'
            owner = objects[fields['owner_path']]
            raise Invalid, 'snapshot owner identity mismatch' unless
              owner && owner['guid'] == fields['owner_guid']

            Array(fields['clones']).each do |clone_path|
              clone = objects[clone_path]
              raise Invalid, 'inventory clone edge is not closed' unless
                clone && clone['origin'] == path
            end
          elsif fields['origin']
            origin = objects[fields['origin']]
            raise Invalid, 'inventory origin edge is not closed' unless
              origin && origin['type'] == 'snapshot' &&
              Array(origin['clones']).include?(path)
          end
        end
      rescue Format::Invalid, KeyError
        raise Invalid, 'invalid inventory object or edge'
      end
    end
  end
end
