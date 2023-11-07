require 'libosctl'
require 'nodectld/db'
require 'thread'

module NodeCtld
  class MountReporter
    include OsCtl::Lib::Utils::Log

    class << self
      attr_accessor :instance

      def report(*args)
        instance.report(*args)
      end
    end

    def initialize
      self.class.instance = self

      @mutex = Mutex.new
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)

      @mounts = []
    end

    def start
      @thread = Thread.new { report_thread }
    end

    def stop
      @stop = true
      @thread.join
    end

    def report(vps_id, mount_id, state)
      sync do
        @mounts.delete_if do |mnt|
          mnt[:id] == mount_id
        end

        @mounts << {
          vps_id: vps_id,
          id: mount_id,
          state: state
        }
      end
    end

    def log_type
      'mount_reporter'
    end

    protected
    def report_thread
      loop do
        break if @stop

        mnt = sync { @mounts.pop }

        if mnt.nil?
          sleep(1)
          next
        end

        log(
          :debug,
          "vps=#{mnt[:vps_id]},mount=##{mnt[:id]},state=#{mnt[:state]}"
        )

        NodeBunny.publish_wait(
          @exchange,
          {
            id: mnt[:id],
            vps_id: mnt[:vps_id],
            state: mnt[:state],
            time: Time.now.to_i,
          }.to_json,
          persistent: true,
          content_type: 'application/json',
          routing_key: 'vps_mounts',
        )
      end
    end

    def sync
      @mutex.synchronize { yield }
    end
  end
end
