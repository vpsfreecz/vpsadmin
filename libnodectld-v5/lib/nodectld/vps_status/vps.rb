require 'libosctl'

module NodeCtld
  class VpsStatus::Vps
    STATE_MAP = {
      Libvirt::Domain::NOSTATE => 'no_state',
      Libvirt::Domain::RUNNING => 'running',
      Libvirt::Domain::BLOCKED => 'blocked',
      Libvirt::Domain::PAUSED => 'paused',
      Libvirt::Domain::SHUTDOWN => 'shutting_down',
      Libvirt::Domain::SHUTOFF => 'stopped',
      Libvirt::Domain::CRASHED => 'crashed',
      Libvirt::Domain::PMSUSPENDED => 'pm_suspended'
    }.freeze

    REASON_MAP = {
      # RUNNING
      Libvirt::Domain::RUNNING_UNKNOWN => 'running_unknown',
      Libvirt::Domain::RUNNING_BOOTED => 'running_booted',
      Libvirt::Domain::RUNNING_MIGRATED => 'running_migrated',
      Libvirt::Domain::RUNNING_RESTORED => 'running_restored',
      Libvirt::Domain::RUNNING_FROM_SNAPSHOT => 'running_from_snapshot',
      Libvirt::Domain::RUNNING_UNPAUSED => 'running_unpaused',
      Libvirt::Domain::RUNNING_MIGRATION_CANCELED => 'running_migration_canceled',
      Libvirt::Domain::RUNNING_SAVE_CANCELED => 'running_save_canceled',
      Libvirt::Domain::RUNNING_WAKEUP => 'running_wakeup',
      Libvirt::Domain::RUNNING_CRASHED => 'running_crashed',

      # BLOCKED
      Libvirt::Domain::BLOCKED_UNKNOWN => 'blocked_unknown',

      # PAUSED
      Libvirt::Domain::PAUSED_UNKNOWN => 'paused_unknown',
      Libvirt::Domain::PAUSED_USER => 'paused_user',
      Libvirt::Domain::PAUSED_MIGRATION => 'paused_migration',
      Libvirt::Domain::PAUSED_SAVE => 'paused_save',
      Libvirt::Domain::PAUSED_DUMP => 'paused_dump',
      Libvirt::Domain::PAUSED_IOERROR => 'paused_ioerror',
      Libvirt::Domain::PAUSED_WATCHDOG => 'paused_watchdog',
      Libvirt::Domain::PAUSED_FROM_SNAPSHOT => 'paused_from_snapshot',
      Libvirt::Domain::PAUSED_SHUTTING_DOWN => 'paused_shutting_down',
      Libvirt::Domain::PAUSED_SNAPSHOT => 'paused_snapshot',
      Libvirt::Domain::PAUSED_CRASHED => 'paused_crashed',

      # SHUTDOWN
      Libvirt::Domain::SHUTDOWN_UNKNOWN => 'shutdown_unknown',
      Libvirt::Domain::SHUTDOWN_USER => 'shutdown_user',

      # SHUTOFF
      Libvirt::Domain::SHUTOFF_UNKNOWN => 'stopped_unknown',
      Libvirt::Domain::SHUTOFF_SHUTDOWN => 'stopped_shutdown',
      Libvirt::Domain::SHUTOFF_DESTROYED => 'stopped_destroyed',
      Libvirt::Domain::SHUTOFF_CRASHED => 'stopped_crashed',
      Libvirt::Domain::SHUTOFF_MIGRATED => 'stopped_migrated',
      Libvirt::Domain::SHUTOFF_SAVED => 'stopped_saved',
      Libvirt::Domain::SHUTOFF_FAILED => 'stopped_failed',
      Libvirt::Domain::SHUTOFF_FROM_SNAPSHOT => 'stopped_from_snapshot',

      # CRASHED
      Libvirt::Domain::CRASHED_UNKNOWN => 'crashed_unknown',
      Libvirt::Domain::CRASHED_PANICKED => 'crashed_panicked',

      # PM SUSPENDED
      Libvirt::Domain::PMSUSPENDED_UNKNOWN => 'pm_suspended_unknown'
    }.freeze

    PROCESS_STATES = %w[R S D Z T t X I].freeze

    PROCESS_COUNTS_COMMAND = <<-END.freeze
      #{PROCESS_STATES.map { |s| "#{s}=0;" }.join(' ')}
      for f in /proc/[0-9]*/stat; do
        IFS= read -r l < "$f" || continue
        s=${l#*) }; s=${s%% *}
        case $s in
          #{PROCESS_STATES.map { |s| "#{s}) #{s}=$((#{s}+1));;" }.join("\n    ")}
          *) continue;;
        esac
      done
      printf "#{PROCESS_STATES.map { |s| "#{s} %s\\n" }.join}" #{PROCESS_STATES.map { |s| "\"$#{s}\"" }.join(' ')}
    END

    include OsCtl::Lib::Utils::Log
    include Utils::Libvirt

    # @return [Integer]
    attr_reader :id

    def initialize(opts)
      @id = opts['id']
      @uuid = opts['uuid']
      @vm_type = opts['vm_type']
      @os = opts['os']
      @os_family = opts['os_family']
      @read_hostname = opts['read_hostname']
      @cgroup_version = opts['cgroup_version']
      @process_states = {}
      @network_interfaces = opts['network_interfaces'].map { |v| VpsStatus::NetworkInterface.new(v) }
      @io_stats = opts['storage_volume_stats'].map { |v| VpsStatus::StorageVolume.new(v) }
      @in_rescue_mode = false
      @qemu_guest_agent = false
      @prev = nil
    end

    def update(domain)
      @time = Time.now
      @delta = @prev ? @time - @prev[:time] : nil

      @exists = true
      @running = domain.active?
      @state, = domain_state_string(*domain.state)

      unless @running
        @prev = nil
        return
      end

      info = domain.info

      if @prev
        dt = @time - @prev[:time]

        @cpu_usage = [((info.cpu_time - @prev[:cpu_time]).to_f / (dt * 1_000_000_000.0)) * 100.0, 0].max

        @memory = get_memory_stats(domain)['rss'] || (info.memory * 1024)

        read_guest_info(domain)
      end

      @prev = {
        time: @time,
        cpu_time: info.cpu_time
      }
    end

    def update_missing
      @time = Time.now
      @exists = false
      @running = false
    end

    def export
      {
        id: @id,
        time: @time.to_i,
        delta: @delta,
        status: @exists,
        state: @state,
        running: @running,
        in_rescue_mode: @in_rescue_mode,
        qemu_guest_agent: @qemu_guest_agent,
        uptime: @uptime,
        loadavg: @loadavg,
        process_count: @nproc,
        used_memory: @memory,
        cpu_usage: @cpu_usage,
        process_states: @process_states,
        volume_stats: @volume_stats,
        io_stats: @io_stats.map(&:export),
        network_stats: @network_interfaces.map(&:export),
        hostname: @hostname
      }
    end

    def log_type
      "vps #{@id}"
    end

    protected

    def domain_state_string(state, reason)
      state_s  = STATE_MAP[state] || "unknown(#{state})"
      reason_s = REASON_MAP[reason] || "unknown(#{reason})"

      [state_s, reason_s]
    end

    def read_guest_info(domain)
      @uptime = 1
      @loadavg = { 1 => 0, 5 => 0, 15 => 0 }
      @nproc = 0

      begin
        domain.qemu_agent_command({ 'execute' => 'guest-ping' }.to_json)
      rescue Libvirt::Error
        @qemu_guest_agent = false
      else
        @qemu_guest_agent = true
      end

      @io_stats.each do |vol_stats|
        vol_stats.set(domain.block_stats(vol_stats.path))
      rescue Libvirt::Error => e
        log(:warn, "Error while getting block stats: #{e.message}")
      end

      @network_interfaces.each do |netif|
        netif.set(domain.ifinfo(netif.host_name))
      rescue Libvirt::Error => e
        log(:warn, "Error while getting netif stats: #{e.message}")
      end

      @volume_stats = read_volume_stats(domain)

      return if @os != 'linux'

      cat_files = %w[/proc/uptime /proc/loadavg]

      if @vm_type == 'qemu_container'
        cat_files << if @cgroup_version == 1
                       '/sys/fs/cgroup/pids/lxc.payload.vps/pids.current'
                     else
                       '/sys/fs/cgroup/lxc.payload.vps/pids.current'
                     end
      end

      begin
        st, out, err = vmexec(domain, %w[cat] + cat_files)
      rescue Libvirt::Error => e
        log(:warn, "Error occurred while reading stats: #{e.message}")
        return
      end

      if st != 0
        log(:warn, "Stats reader exited with #{st}: #{err.inspect}")
      end

      uptime_data, loadavg_data, nproc_cg = out.strip.split("\n")

      begin
        @uptime = SystemProbes::Uptime.new(uptime_data || '').uptime
      rescue ParserError
        # pass
      end

      begin
        @loadavg = SystemProbes::LoadAvg.new(loadavg_data || '').avg
      rescue ParserError
        # pass
      end

      if nproc_cg
        @nproc = nproc_cg.to_i
      else
        _, nproc_sh = vmexec(domain, ['sh', '-c', 'echo /proc/[0-9]* | wc -w'])
        @nproc = nproc_sh.to_i
      end

      @process_states =
        begin
          read_process_counts(domain) || {}
        rescue Libvirt::Error => e
          log(:warn, "Error occurred while reading stats: #{e.message}")
          {}
        end

      return unless @read_hostname

      begin
        st, out, =
          if @vm_type == 'qemu_container'
            vmctexec(domain, %w[cat /proc/sys/kernel/hostname])
          else
            vmexec(domain, %w[cat /proc/sys/kernel/hostname])
          end
      rescue Libvirt::Error => e
        log(:warn, "Error occurred while reading hostname: #{e.message}")
        return
      end

      if st == 0
        @hostname = out.strip
      else
        log(:warn, "Hostname reader exited with #{st}: #{err.inspect}")
        @hostname = 'unable-to-read'
      end
    end

    def read_volume_stats(domain)
      begin
        fsinfo = JSON.parse(domain.qemu_agent_command({ 'execute' => 'guest-get-fsinfo' }.to_json))['return']
      rescue Libvirt::Error => e
        log(:warn, "Error occurred while getting fsinfo: #{e.message}")
        return []
      end

      ret = []

      fsinfo.each do |fs|
        vol_id = nil

        fs['disk'].each do |disk|
          next if /\Avpsadmin-volume-(\d+)\z/ !~ disk['serial']

          vol_id = ::Regexp.last_match(1).to_i
          break
        end

        next if vol_id.nil? || vol_id <= 0

        ret << {
          id: vol_id,
          total_bytes: fs['total-bytes'],
          total_bytes_privileged: fs['total-bytes-privileged'],
          used_bytes: fs['used-bytes'],
          filesystem: fs['type']
        }
      end

      ret
    end

    def read_process_counts(domain)
      cmd = ['sh', '-c', PROCESS_COUNTS_COMMAND]
      t = Time.now

      st, out, =
        if @vm_type == 'qemu_container'
          vmctexec(domain, cmd)
        else
          vmexec(domain, cmd)
        end

      return if st != 0

      processes = PROCESS_STATES.to_h { |s| [s, 0] }

      out.strip.split("\n").each do |line|
        state, n_str = line.strip.split
        next unless PROCESS_STATES.include?(state)

        processes[state] = n_str.to_i
      end

      processes
    end

    def get_memory_stats(domain)
      ret = {}

      domain.memory_stats.each do |st|
        key =
          case st.tag
          when Libvirt::Domain::MemoryStats::ACTUAL_BALLOON
            'actual'
          when Libvirt::Domain::MemoryStats::AVAILABLE
            'available'
          when Libvirt::Domain::MemoryStats::MAJOR_FAULT
            'major_fault'
          when Libvirt::Domain::MemoryStats::MINOR_FAULT
            'minor_fault'
          when Libvirt::Domain::MemoryStats::RSS
            'rss'
          when Libvirt::Domain::MemoryStats::SWAP_IN
            'swap_in'
          when Libvirt::Domain::MemoryStats::SWAP_OUT
            'swap_out'
          when Libvirt::Domain::MemoryStats::UNUSED
            'unused'
          end

        next if key.nil?

        # libvirt returns values in kB
        ret[key] = st.instance_variable_get('@val') * 1024
      end

      ret
    end
  end
end
