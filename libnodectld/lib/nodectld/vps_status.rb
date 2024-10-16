require 'etc'
require 'time'
require 'libosctl'
require 'nodectld/utils'
require 'nodectld/exceptions'
require 'nodectld/system_probes'

module NodeCtld
  class VpsStatus
    class Entry
      attr_reader :id, :read_hostname
      attr_accessor :exists, :running, :hostname, :uptime, :cpu_usage, :memory,
                    :nproc, :loadavg, :in_rescue_mode

      def initialize(row)
        @skip = false
        @id = row['id'].to_s
        @read_hostname = row['read_hostname']
        @in_rescue_mode = false
      end

      alias read_hostname? read_hostname
      alias exists? exists
      alias running? running

      def skip
        @skip = true
      end

      def skip?
        @skip
      end
    end

    include OsCtl::Lib::Utils::Log
    include Utils::System
    include Utils::OsCtl
    include Utils::Vps

    @@mutex = Mutex.new

    def initialize
      @tics_per_sec = Etc.sysconf(Etc::SC_CLK_TCK).to_i
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
    end

    # @param top_data [Hash] data from osctl ct top
    def update(top_data)
      @@mutex.synchronize do
        @top_data = top_data
        @host_uptime = SystemProbes::Uptime.new.uptime

        safe_update
      end
    end

    def safe_update
      vpsadmin_vpses = {}

      fetch_vpses.each do |vps|
        ent = Entry.new(vps)
        vpsadmin_vpses[ent.id.to_s] = ent
      end

      t = Time.now
      cts = ct_list

      begin
        lavgs = OsCtl::Lib::LoadAvgReader.read_for(cts)
      rescue StandardError => e
        log(:warn, :vps_status, "Unable to read load averages: #{e.message} (#{e.class})")
        lavgs = {}
      end

      hostname_vpsadmin_vpses = []

      cts.each do |vps|
        vpsadmin_vps = vpsadmin_vpses[vps[:id]]
        next if vpsadmin_vps.nil?

        vpsadmin_vps.exists = true
        vpsadmin_vps.running = vps[:state] == 'running'

        next unless vpsadmin_vps.running?

        # Find matching stats from ct top
        apply_usage_stats(vpsadmin_vps)

        run_or_skip(vpsadmin_vps) do
          vpsadmin_vps.uptime = read_uptime(vps[:init_pid])
        end

        # Set loadavg
        lavg = lavgs["#{vps[:pool]}:#{vps[:id]}"]

        vpsadmin_vps.loadavg = (lavg.avg if lavg)

        # Read hostname if it isn't managed by vpsAdmin
        if vpsadmin_vps.read_hostname?
          hostname_vpsadmin_vpses << vpsadmin_vps
          vpsadmin_vps.hostname = 'unable-to-read'
        end

        # Detect osctl ct boot
        if vps[:dataset] != vps[:boot_dataset] && %r{/ct/\d+\.boot-\w+\z} =~ vps[:boot_dataset]
          vpsadmin_vps.in_rescue_mode = true
        end
      end

      # Query hostname of VPSes with manual configuration
      if hostname_vpsadmin_vpses.any?
        begin
          osctl_parse(
            %i[ct ls],
            hostname_vpsadmin_vpses.map(&:id),
            { output: %w[id hostname_readout].join(',') }
          ).each do |ct|
            vpsadmin_vpses[ct[:id]].hostname = ct[:hostname_readout] || 'unable-to-read'
          end
        rescue SystemCommandFailed => e
          log(:warn, :vps_status, "Unable to read VPS hostnames: #{e.message}")
        end
      end

      # Send results to supervisor
      vpsadmin_vpses.each_value do |vps|
        next unless vps.exists?

        NodeBunny.publish_wait(
          @exchange,
          {
            id: vps.id.to_i,
            time: t.to_i,
            status: !vps.skip?,
            running: vps.running?,
            in_rescue_mode: vps.in_rescue_mode,
            uptime: vps.uptime,
            loadavg: vps.loadavg,
            process_count: vps.nproc,
            used_memory: vps.memory,
            cpu_usage: vps.cpu_usage,
            hostname: vps.hostname
          }.to_json,
          content_type: 'application/json',
          routing_key: 'vps_statuses'
        )
      end
    rescue SystemCommandFailed => e
      log(:fatal, :vps_status, e.message)
    end

    protected

    def fetch_vpses
      RpcClient.run(&:list_vps_status_check)
    end

    def ct_list
      osctl_parse(%i[ct ls])
    end

    def run_or_skip(vps)
      yield
    rescue StandardError => e
      log(:warn, :vps, e.message)
      vps.skip
    end

    def apply_usage_stats(vps)
      st = @top_data.detect { |ct| ct[:id] == vps.id }

      # It may happen that `osctl ct top` does not yet have information
      # about a newly started VPS.
      unless st
        log(:warn, :vps, "VPS #{vps.id} not found in ct top")
        vps.skip
        return
      end

      vps.cpu_usage = st[:cpu_usage]
      vps.memory = st[:memory] # in bytes
      vps.nproc = st[:nproc]
    end

    # Read the container's uptime
    #
    # The uptime of the container can be thought of as the time since its
    # init process has started. Process start time can be found in
    # `/proc/<pid>/stat`, the 22nd field, see proc(5). The value is stored
    # in clock ticks since the system boot, so we divide that by ticks per
    # second, and substract it from the host's uptime.
    #
    # @param init_pid [String,Integer]
    def read_uptime(init_pid)
      f = File.open(File.join('/proc', init_pid.to_s, 'stat'), 'r')
      str = f.readline.strip
      f.close

      @host_uptime - (str.split[21].to_i / @tics_per_sec)
    end
  end
end
