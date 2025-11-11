require 'time'
require 'libosctl'
require 'nodectld/utils'
require 'nodectld/exceptions'
require 'singleton'

module NodeCtld
  class VpsStatus
    include Singleton
    include OsCtl::Lib::Utils::Log

    class << self
      %i[start stop update add_vps remove_vps].each do |v|
        define_method(v) do |*args, **kwargs, &block|
          instance.send(v, *args, **kwargs, &block)
        end
      end
    end

    def initialize
      @queue = Queue.new
      @vpses = {}
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
    end

    def start
      @thread = Thread.new { status_loop }
    end

    def stop
      @queue << [:stop]
      @thread.join
      nil
    end

    def update
      @queue << [:update]
      nil
    end

    # @param vps_id [Integer]
    def add_vps(vps_id)
      @queue << [:add_vps, vps_id]
      nil
    end

    # @param vps_id [Integer]
    def remove_vps(vps_id)
      @queue << [:remove_vps, vps_id]
      nil
    end

    def log_type
      'vps status'
    end

    protected

    def status_loop
      @vpses = fetch_all_vpses.to_h do |vps|
        [vps['id'], VpsStatus::Vps.new(vps)]
      end

      loop do
        cmd, *args = @queue.pop(timeout: $CFG.get(:vpsadmin, :vps_status_interval))

        case cmd
        when :stop
          break
        when :update
          # pass
        when :add_vps
          vps_id, = args
          do_add_vps(vps_id)
        when :remove_vps
          vps_id, = args
          do_remove_vps(vps_id)
        end

        vps_statuses = @vpses.clone
        conn = LibvirtClient.new

        domains = conn.list_all_domains

        log(:debug, "Updating status of #{vps_statuses.length} VPS / #{domains.length} domains")

        domains.each do |domain|
          vps_id = domain.name.to_i
          next if vps_id <= 0

          vps = vps_statuses.delete(vps_id)

          if vps.nil?
            vps = get_vps(vps_id)

            # TODO: we could remember that the VPS does not exist
            next if vps.nil?

            @vpses[vps.id] = vps
          end

          vps.update(domain)

          report_status(vps.export)
        end

        vps_statuses.each_value do |vps|
          log(:debug, "Domain for VPS #{vps.id} not found")
          vps.update_missing
          report_status(vps.export)
        end

        conn.close
      end
    end

    def fetch_all_vpses
      RpcClient.run(&:list_vps_status_check)
    end

    def fetch_vps(vps_id)
      RpcClient.run { |rpc| rpc.get_vps_status_check(vps_id) }
    end

    def get_vps(vps_id)
      vps_opts = fetch_vps(vps_id)
      return if vps_opts.nil?

      VpsStatus::Vps.new(vps_opts)
    end

    def do_add_vps(vps_id)
      vps = get_vps(vps_id)
      return if vps.nil?

      @vpses[vps.id] = vps
    end

    def do_remove_vps(vps_id)
      @vpses.delete(vps_id)
    end

    def report_status(status)
      NodeBunny.publish_wait(
        @exchange,
        status.to_json,
        content_type: 'application/json',
        routing_key: 'vps_statuses'
      )
    end
  end
end
