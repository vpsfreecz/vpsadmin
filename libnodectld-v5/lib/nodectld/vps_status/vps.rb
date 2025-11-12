require 'libosctl'

module NodeCtld
  class VpsStatus::Vps
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

      # TODO: detect rescue mode

      @prev = {
        time: @time,
        cpu_time: info.cpu_time,
        io_stats: @io_stats
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
        running: @running,
        in_rescue_mode: @in_rescue_mode,
        qemu_guest_agent: @qemu_guest_agent,
        uptime: @uptime,
        loadavg: @loadavg,
        process_count: @nproc,
        used_memory: @memory,
        cpu_usage: @cpu_usage,
        process_states: @process_states,
        io_stats: @io_stats.map(&:export),
        network_stats: @network_interfaces.map(&:export),
        hostname: @hostname
      }
    end

    def log_type
      "vps #{@id}"
    end

    protected

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
        vol_stats.set(domain.block_stats(vol_stats.path), @prev[:io_stats])
      end

      @network_interfaces.each do |netif|
        netif.set(domain.ifinfo(netif.host_name))
      end

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

      @process_states = read_process_counts(domain) || {}

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
