require 'etc'
require 'time'
require 'libosctl'
require 'nodectld/utils'
require 'nodectld/exceptions'
require 'nodectld/system_probes'
require 'nodectld/vps_autostart_status'

module NodeCtld
  class VpsStatus
    class Entry
      attr_reader :id, :read_hostname
      attr_accessor :exists, :running, :hostname, :uptime, :cpu_usage, :memory,
                    :nproc, :loadavg, :in_rescue_mode, :usage_source

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

    attr_reader :vps_autostart_status

    def initialize
      @tics_per_sec = Etc.sysconf(Etc::SC_CLK_TCK).to_i
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
      @vps_autostart_status = VpsAutostartStatus.new
    end

    # @param sample [CtTop::Sample] data from osctl ct top
    def update(sample)
      @@mutex.synchronize do
        @sample = sample
        @host_uptime = SystemProbes::Uptime.new.uptime

        safe_update
      end
    end

    def safe_update
      fetched_vpses = fetch_vpses
      vpsadmin_vpses = fetched_vpses.filter_map do |vps|
        pool_fs = vps['pool_fs']
        next unless pool_fs.is_a?(String) && !pool_fs.empty?

        [[pool_fs.split('/', 2).first, vps.fetch('id').to_s], Entry.new(vps)]
      end.to_h

      t = Time.now
      grouped_cts = ct_list.group_by { |ct| [ct.pool, ct.id] }
      cts = grouped_cts.values.filter_map { |rows| rows.first if rows.one? }
      if cts.length == grouped_cts.length
        update_vps_autostart_status(fetched_vpses, cts, now: t)
      else
        @vps_autostart_status.failed
        log(:warn, :vps_status, 'Container list contains duplicate identities')
      end

      begin
        lavgs = OsCtl::Lib::LoadAvgReader.read_for(cts)
      rescue StandardError => e
        log(:warn, :vps_status, "Unable to read load averages: #{e.message} (#{e.class})")
        lavgs = {}
      end

      hostname_vpsadmin_vpses = []

      cts.each do |ct|
        vpsadmin_vps = vpsadmin_vpses[[ct.pool, ct.id]]
        state = ct.state
        next unless vpsadmin_vps && %w[running stopped].include?(state)

        vpsadmin_vps.exists = true
        vpsadmin_vps.running = state == 'running'

        next unless vpsadmin_vps.running?

        run_or_skip(vpsadmin_vps) do
          start_ticks = read_init_start_ticks(ct.init_pid)
          vpsadmin_vps.uptime = @host_uptime - (start_ticks / @tics_per_sec)
          vpsadmin_vps.usage_source = [ct, start_ticks]
        end

        # Set loadavg
        lavg = lavgs["#{ct.pool}:#{ct.id}"]

        vpsadmin_vps.loadavg = (lavg.avg if lavg)

        # Read hostname if it isn't managed by vpsAdmin
        if vpsadmin_vps.read_hostname?
          hostname_vpsadmin_vpses << vpsadmin_vps
          vpsadmin_vps.hostname = 'unable-to-read'
        end

        # Detect osctl ct boot
        if ct.in_ct_boot?
          vpsadmin_vps.in_rescue_mode = true
        end
      end

      # Query hostname of VPSes with manual configuration
      if hostname_vpsadmin_vpses.any?
        begin
          osctl_parse(
            %i[ct ls],
            hostname_vpsadmin_vpses.map(&:id),
            { output: %w[pool id hostname_readout].join(',') }
          ).each do |ct|
            vps = vpsadmin_vpses[ct.values_at(:pool, :id)]
            vps.hostname = ct[:hostname_readout] || 'unable-to-read' if vps
          end
        rescue SystemCommandFailed => e
          log(:warn, :vps_status, "Unable to read VPS hostnames: #{e.message}")
        end
      end

      # Send results to supervisor
      vpsadmin_vpses.each_value do |vps|
        next unless vps.exists?

        run_or_skip(vps) { apply_usage_stats(vps) } if vps.running? && !vps.skip?
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
    rescue SystemCommandFailed, RpcClient::Error => e
      @vps_autostart_status.failed
      log(:fatal, :vps_status, e.message)
    rescue StandardError
      @vps_autostart_status.failed
      raise
    end

    protected

    def fetch_vpses
      RpcClient.run(&:list_vps_status_check)
    end

    def ct_list
      # This lookup supplies identity and state, not cgroup usage. In
      # particular, a missing Top measurement must not break the inventory.
      fields = %w[pool id group_path init_pid state autostart boot_dataset dataset]
      osctl_parse(%i[ct ls], [], output: fields.join(',')).map { |v| OsCtlContainer.new(v) }
    end

    def update_vps_autostart_status(vpses, cts, now:)
      @vps_autostart_status.update(vpses, cts, now:)
    rescue VpsAutostartStatus::UnsupportedResponse => e
      @vps_autostart_status.failed
      log(:warn, :vps_autostart_status, e.message)
    end

    def run_or_skip(vps)
      yield
    rescue StandardError => e
      log(:warn, :vps, e.message)
      vps.skip
    end

    def apply_usage_stats(vps)
      ct, start_ticks = vps.usage_source
      if @sample && read_init_start_ticks(ct.init_pid) != start_ticks
        vps.skip
        return
      end

      now = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      usage = @sample&.usage(ct, start_ticks:, now_ns: now)
      if usage
        vps.cpu_usage, vps.memory, vps.nproc = usage
      else
        vps.skip
      end
    end

    # Field 22 is the start time in clock ticks. The process name can contain
    # spaces and closing parentheses, so split only after the last ')'.
    def read_init_start_ticks(init_pid)
      raise ArgumentError, 'Missing container init PID' unless init_pid.is_a?(Integer) && init_pid > 0

      proc_stat = File.read("/proc/#{init_pid}/stat")
      closing = proc_stat.rindex(')')
      raise ArgumentError, 'Invalid container init stat' unless closing && proc_stat.start_with?("#{init_pid} (")

      fields = proc_stat[(closing + 1)..].split
      ticks = Integer(fields.fetch(19), 10)
      raise ArgumentError, 'Invalid container init identity' unless ticks > 0 && !%w[Z X x].include?(fields.first)

      ticks
    end
  end
end
