require 'digest'
require 'bigdecimal'
require 'json'
require 'open3'
require 'securerandom'
require 'time'
require 'timeout'

module NodeCtld
  # Read-only whole-zpool scan. A final marker is published only after both
  # passes prove the same exact ordered inventory.
  class StorageInventory
    class Invalid < StandardError; end

    VERSION = 1
    HANDLE = 5290
    MAX_CHUNK_ROWS = 100
    MAX_CHUNK_BYTES = 64 * 1024
    MAX_FILESYSTEMS = 200_000
    MAX_OBJECTS = 200_000
    MAX_SCAN_SECONDS = 2 * 60 * 60
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
    PROPERTIES = %w[name type guid origin clones userrefs defer_destroy creation createtxg].freeze

    def self.run!(command, params, scanner: nil, publisher: nil, now: -> { Time.now.utc })
      request = Request.new(command, params, now:).validate!
      scanner ||= Scanner.new(command, request, now:)
      publisher ||= Publisher.new(request)
      new(request, scanner, publisher, now:).run!
    ensure
      publisher&.close
    end

    def initialize(request, scanner, publisher, now:)
      @request = request
      @scanner = scanner
      @publisher = publisher
      @now = now
      @sequence = 0
      @chunk_chain = Digest::SHA256.hexdigest('')
      @count = 0
    end

    def run!
      first = scan_pass(emit: true)
      flush_chunk
      second = scan_pass(emit: false)
      raise Invalid, 'inventory changed between passes' unless
        first['digest'] == second['digest'] && first['count'] == second['count'] &&
        first['zpool_guid'] == second['zpool_guid'] && first['roots'] == second['roots']

      final = envelope('final', {
        'sequence' => @sequence, 'chunk_chain' => @chunk_chain,
        'row_count' => @count, 'chunk_count' => @sequence,
        'first' => first, 'second' => second
      })
      publish!(final)
      { inventory_version: VERSION, object_count: @count,
        inventory_digest: first['digest'], chunk_chain: @chunk_chain }
    end

    private

    def scan_pass(emit:)
      check_deadline!
      started = @now.call.iso8601(6)
      digest = Digest::SHA256.new
      count = 0
      roots = {}
      zpool_guid = @scanner.zpool_guid
      if @request.zpool_guid && zpool_guid != @request.zpool_guid
        raise Invalid, 'zpool GUID differs from signed request'
      end

      @scanner.each_record do |fields|
        check_deadline!
        record = self.class.record(fields)
        encoded = "#{self.class.canonical(record)}\n"
        raise Invalid, 'inventory row exceeds chunk limit' if encoded.bytesize > MAX_CHUNK_BYTES / 2

        digest.update(encoded)
        count += 1
        raise Invalid, 'inventory object limit exceeded' if count > MAX_OBJECTS

        roots[fields.fetch('path')] = fields.fetch('guid') if @request.roots.include?(fields.fetch('path'))
        add_record(record) if emit
      end
      raise Invalid, 'managed root missing from scan' unless roots.keys.sort == @request.roots.sort

      { 'observed_from_at' => started, 'observed_until_at' => @now.call.iso8601(6),
        'digest' => digest.hexdigest, 'count' => count, 'zpool_guid' => zpool_guid,
        'roots' => roots.sort.to_h }
    end

    def add_record(record)
      @chunk ||= []
      candidate = @chunk + [record]
      frame = envelope('chunk', {
        'sequence' => @sequence, 'records' => candidate,
        'row_count' => candidate.length,
        'records_bytes' => candidate.sum { |row| self.class.canonical(row).bytesize + 1 },
        'records_digest' => self.class.digest(candidate)
      })
      if candidate.length > MAX_CHUNK_ROWS || self.class.canonical(frame).bytesize > MAX_CHUNK_BYTES
        flush_chunk
        @chunk = [record]
      else
        @chunk = candidate
      end
      @count += 1
    end

    def flush_chunk
      return if @chunk.nil? || @chunk.empty?

      frame = envelope('chunk', {
        'sequence' => @sequence, 'records' => @chunk,
        'row_count' => @chunk.length,
        'records_bytes' => @chunk.sum { |row| self.class.canonical(row).bytesize + 1 },
        'records_digest' => self.class.digest(@chunk)
      })
      raise Invalid, 'chunk exceeds byte limit' if self.class.canonical(frame).bytesize > MAX_CHUNK_BYTES

      publish!(frame)
      @chunk_chain = Digest::SHA256.hexdigest(@chunk_chain + frame.fetch('digest'))
      @sequence += 1
      @chunk = []
    end

    def envelope(type, fields)
      unsigned = {
        'type' => type, 'version' => VERSION,
        'run_uuid' => @request.run_uuid, 'attempt_uuid' => @request.attempt_uuid,
        'node_id' => @request.node_id.to_s, 'pool_id' => @request.pool_id.to_s,
        'zpool' => @request.zpool, 'managed_root' => @request.managed_root,
        'roots' => @request.roots,
        'nonce' => @request.nonce
      }.merge(fields)
      unsigned.merge('digest' => self.class.digest(unsigned))
    end

    def publish!(frame)
      check_deadline!
      encoded = self.class.canonical(frame)
      raise Invalid, 'frame exceeds byte limit' if encoded.bytesize > MAX_CHUNK_BYTES

      @publisher.publish(encoded)
    end

    def check_deadline!
      raise Invalid, 'inventory deadline elapsed' if @now.call >= @request.deadline
    end

    class << self
      def canonical(value)
        JSON.generate(sort(value))
      end

      def digest(value)
        Digest::SHA256.hexdigest(canonical(value))
      end

      def record(fields)
        unsigned = { 'kind' => 'zfs_object', 'version' => VERSION, 'fields' => sort(fields) }
        unsigned.merge('digest' => digest(unsigned))
      end

      def sort(value)
        case value
        when Hash
          value.transform_keys(&:to_s).sort.to_h.transform_values { |v| sort(v) }
        when Array
          value.map { |v| sort(v) }
        else
          value
        end
      end
    end

    class Request
      attr_reader :run_uuid, :attempt_uuid, :node_id, :pool_id, :zpool,
                  :zpool_guid, :managed_root, :roots, :routing_key, :nonce, :deadline

      def initialize(command, params, now:)
        @command = command
        @params = params.transform_keys(&:to_sym)
        @now = now
      end

      def validate!
        raise Invalid, 'inventory command is unsigned' if @command.trans['signature'].to_s.empty?
        unless TransactionVerifier.verify_base64(
          @command.trans['input'], @command.trans['signature']
        )
          raise Invalid, 'inventory signature is invalid'
        end
        raise Invalid, 'wrong inventory handle' unless @command.trans['handle'].to_i == HANDLE
        raise Invalid, 'unsupported inventory protocol' unless @params[:protocol_version] == VERSION

        @run_uuid = @params.fetch(:run_uuid)
        @attempt_uuid = @params.fetch(:attempt_uuid)
        raise Invalid, 'invalid inventory UUID' unless UUID.match?(@run_uuid) && UUID.match?(@attempt_uuid)

        @node_id = Integer(@params.fetch(:node_id))
        @pool_id = Integer(@params.fetch(:pool_id))
        raise Invalid, 'wrong node' unless @node_id == $CFG.get(:vpsadmin, :node_id).to_i &&
                                           @node_id == @command.trans['node_id'].to_i

        @zpool = @params.fetch(:zpool)
        @managed_root = @params.fetch(:managed_root)
        @roots = @params.fetch(:roots)
        @zpool_guid = @params[:zpool_guid]&.to_s
        @nonce = @params.fetch(:nonce)
        @routing_key = @params.fetch(:routing_key)
        raise Invalid, 'invalid inventory scope' unless
          @zpool.is_a?(String) && @zpool.match?(/\A[a-zA-Z0-9_.:-]+\z/) &&
          @managed_root.is_a?(String) && @managed_root.split('/').first == @zpool &&
          @roots.is_a?(Array) && @roots.all?(String) &&
          @roots.uniq.sort == @roots.sort && @roots.include?(@managed_root) &&
          @nonce.is_a?(String) && @nonce.match?(/\A[0-9a-f]{64}\z/) &&
          @routing_key == "storage_inventory:#{@run_uuid}"
        raise Invalid, 'invalid expected zpool GUID' if @zpool_guid && !@zpool_guid.match?(/\A\d+\z/)

        @deadline = Time.iso8601(@params.fetch(:deadline))
        raise Invalid, 'invalid inventory deadline' unless
          @deadline > @now.call && @deadline <= @now.call + MAX_SCAN_SECONDS

        check_catalog!
        self
      rescue KeyError, ArgumentError
        raise Invalid, 'malformed signed inventory request'
      end

      private

      def check_catalog!
        Db.open do |db|
          pool = db.prepared(
            'SELECT id, node_id, filesystem, zpool_guid FROM pools WHERE id = ?', pool_id
          ).get
          raise Invalid, 'Pool is missing or on another node' unless pool &&
                                                                     pool['node_id'].to_i == node_id
          raise Invalid, 'managed root differs from Pool' unless
            pool['filesystem'] == managed_root && managed_root.split('/').first == zpool
          if pool['zpool_guid'] && decimal_guid(pool['zpool_guid']) != zpool_guid
            raise Invalid, 'expected zpool GUID differs from Pool'
          end

          catalog_roots = []
          db.prepared(
            'SELECT filesystem FROM pools WHERE node_id = ?', node_id
          ).each do |row|
            root = row['filesystem']
            catalog_roots << root if root.split('/').first == zpool
          end
          catalog_roots.sort!
          raise Invalid, 'managed roots differ from catalog' unless catalog_roots == roots.sort
        end
      end

      def decimal_guid(value)
        raw = value.is_a?(BigDecimal) ? value.to_s('F') : value.to_s
        raise Invalid, 'invalid Pool GUID' unless raw.match?(/\A\d+(?:\.0+)?\z/)

        raw.split('.').first
      end
    end

    class Scanner
      def initialize(command, request, now:)
        @command = command
        @request = request
        @now = now
      end

      def zpool_guid
        output = +''
        each_process_line([$CFG.get(:bin, :zpool), 'list', '-H', '-p', '-o', 'guid', @request.zpool]) do |line|
          output << line
          raise Invalid, 'zpool GUID response is too large' if output.bytesize > 64
        end
        guid = output.strip
        raise Invalid, 'zpool GUID query failed' unless guid.match?(/\A\d+\z/)

        guid
      end

      def each_record
        filesystem_guids = {}
        command = [$CFG.get(:bin, :zfs), 'list', '-H', '-p', '-r', '-s', 'name',
                   '-t', 'filesystem,volume,snapshot', '-o', PROPERTIES.join(','),
                   @request.zpool]
        each_process_line(command) do |line|
          raise Invalid, 'inventory deadline elapsed' if @now.call >= @request.deadline

          fields = line.chomp.split("\t", -1)
          raise Invalid, 'malformed ZFS inventory row' unless fields.length == PROPERTIES.length

          path, type, guid, origin, clones, userrefs, deferred, creation, txg = fields
          raise Invalid, 'invalid ZFS path or GUID' unless
            path.start_with?("#{@request.zpool}/", "#{@request.zpool}@") ||
            path == @request.zpool
          raise Invalid, 'invalid ZFS GUID' unless guid.match?(/\A\d+\z/)
          raise Invalid, 'unsupported ZFS object type' unless %w[filesystem volume snapshot].include?(type)

          if type == 'snapshot'
            owner = path.split('@', 2).first
            owner_guid = filesystem_guids[owner]
            raise Invalid, 'snapshot owner was not listed' unless owner_guid
          else
            raise Invalid, 'too many filesystems in inventory' if filesystem_guids.size >= MAX_FILESYSTEMS

            filesystem_guids[path] = guid
            owner = nil
            owner_guid = nil
          end

          yield({
            'path' => path, 'type' => type, 'guid' => guid,
            'owner_path' => owner, 'owner_guid' => owner_guid,
            'origin' => origin == '-' ? nil : origin,
            'clones' => clones == '-' ? [] : clones.split(',').sort,
            'userrefs' => userrefs == '-' ? { 'unavailable' => true } : decimal!(userrefs),
            'deferred_destroy' => deferred == '-' ? { 'unavailable' => true } : deferred,
            'creation' => creation == '-' ? { 'unavailable' => true } : decimal!(creation),
            'createtxg' => txg == '-' ? { 'unavailable' => true } : decimal!(txg)
          })
        end
      end

      private

      def each_process_line(command)
        remaining = @request.deadline - @now.call
        raise Invalid, 'inventory deadline elapsed' if remaining <= 0

        Timeout.timeout(remaining) do
          Open3.popen3(*command) do |input, output, stderr, wait|
            input.close
            handler = Thread.current[:command]
            handler.subtask = wait.pid if handler
            reader = Thread.new do
              loop { stderr.readpartial(4096) }
            rescue EOFError
              nil
            end
            begin
              output.each_line("\n", MAX_CHUNK_BYTES) do |line|
                raise Invalid, 'oversize or unterminated inventory line' unless line.end_with?("\n")

                yield line
              end
              reader.join
              raise Invalid, 'ZFS inventory command failed' unless wait.value.success?
            ensure
              unless wait.join(0)
                begin
                  Process.kill('TERM', wait.pid)
                rescue Errno::ESRCH
                  nil
                end
                unless wait.join(1)
                  begin
                    Process.kill('KILL', wait.pid)
                  rescue Errno::ESRCH
                    nil
                  end
                  raise Invalid, 'inventory child did not exit' unless wait.join(2)
                end
              end
              handler.subtask = nil if handler
              reader.kill if reader.alive?
            end
          end
        end
      rescue Timeout::Error
        raise Invalid, 'inventory subprocess deadline elapsed'
      end

      def decimal!(value)
        raise Invalid, 'malformed ZFS numeric property' unless value.match?(/\A\d+\z/)

        value
      end
    end

    class Publisher
      def initialize(request)
        @request = request
        open_channel!
      end

      def publish(payload)
        3.times do |attempt|
          remaining = @request.deadline - Time.now.utc
          raise Invalid, 'inventory publisher deadline elapsed' if remaining <= 0

          begin
            Timeout.timeout([remaining, 30].min) do
              @returned = false
              @exchange.publish(
                payload, routing_key: @request.routing_key, persistent: true,
                         mandatory: true, content_type: 'application/json'
              )
              raise Invalid, 'inventory publish was not confirmed' unless @channel.wait_for_confirms
              raise Invalid, 'inventory message was unroutable' if @returned
            end
            break
          rescue Invalid => e
            raise if e.message == 'inventory message was unroutable' || attempt == 2
          rescue StandardError
            raise Invalid, 'inventory publish failed' if attempt == 2
          end

          close
          open_channel!
        end
      end

      def close
        Timeout.timeout(2) { @channel&.close }
      rescue StandardError
        nil
      end

      private

      def open_channel!
        remaining = @request.deadline - Time.now.utc
        raise Invalid, 'inventory publisher deadline elapsed' if remaining <= 0

        Timeout.timeout([remaining, 30].min) do
          @channel = NodeBunny.create_channel
          @channel.confirm_select
          @exchange = @channel.direct(NodeBunny.exchange_name, durable: true)
          @returned = false
          @exchange.on_return { |_delivery, _metadata, _payload| @returned = true }
        end
      rescue Timeout::Error
        raise Invalid, 'inventory publisher setup timed out'
      end
    end
  end
end
