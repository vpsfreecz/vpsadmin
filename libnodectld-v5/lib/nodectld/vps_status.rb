require 'etc'
require 'time'
require 'libosctl'
require 'nodectld/utils'
require 'nodectld/exceptions'

module NodeCtld
  class VpsStatus
    class Entry
      attr_reader :id, :uuid, :vm_type, :os, :os_family, :read_hostname, :cgroup_version
      attr_accessor :exists, :running, :hostname, :uptime, :cpu_usage, :memory,
                    :nproc, :loadavg, :in_rescue_mode

      def initialize(row)
        @skip = false
        @id = row['id'].to_s
        @uuid = row['uuid']
        @vm_type = row['vm_type']
        @os = row['os']
        @os_family = row['os_family']
        @read_hostname = row['read_hostname']
        @cgroup_version = row['cgroup_version']
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
    include Utils::System
    include Utils::Libvirt
    include Utils::Vps

    @@mutex = Mutex.new

    def initialize
      @prev = {}
      @channel = NodeBunny.create_channel
      @exchange = @channel.direct(NodeBunny.exchange_name)
    end

    def update
      @@mutex.synchronize do
        safe_update
      end
    end

    def safe_update
      vpsadmin_vpses = {}

      fetch_vpses.each do |vps|
        ent = Entry.new(vps)
        vpsadmin_vpses[ent.uuid] = ent
      end

      conn = LibvirtClient.new
      domains = conn.list_all_domains

      hostname_vpsadmin_vpses = []

      domains.each do |dom|
        t = Time.now

        vpsadmin_vps = vpsadmin_vpses[dom.uuid]
        next if vpsadmin_vps.nil?

        vpsadmin_vps.exists = true
        vpsadmin_vps.running = dom.active?

        unless vpsadmin_vps.running?
          report_status(vpsadmin_vps, t)
          next
        end

        prev = @prev[dom.uuid]
        info = dom.info

        if prev
          dt = t - prev[:time]

          vpsadmin_vps.cpu_usage = [((info.cpu_time - prev[:cpu_time]).to_f / (dt * 1_000_000_000.0)) * 100.0, 0].max

          vpsadmin_vps.memory = get_memory_stats(dom)['rss'] || (info.memory * 1024)

          read_guest_info(vpsadmin_vps, dom)
        end

        # TODO: detect rescue mode

        @prev[dom.uuid] = {
          time: t,
          cpu_time: info.cpu_time
        }

        report_status(vpsadmin_vps, t)
      end
    rescue SystemCommandFailed => e
      log(:fatal, :vps_status, e.message)
    end

    protected

    def fetch_vpses
      RpcClient.run(&:list_vps_status_check)
    end

    def run_or_skip(vps)
      yield
    rescue StandardError => e
      log(:warn, :vps, e.message)
      vps.skip
    end

    def get_memory_stats(dom)
      ret = {}

      dom.memory_stats.each do |st|
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

    def read_guest_info(vpsadmin_vps, dom)
      vpsadmin_vps.uptime = 1
      vpsadmin_vps.loadavg = { 1 => 0, 5 => 0, 15 => 0 }
      vpsadmin_vps.nproc = 0

      return if vpsadmin_vps.os != 'linux'

      cat_files = %w[/proc/uptime /proc/loadavg]

      if vpsadmin_vps.vm_type == 'qemu_container'
        cat_files << if vpsadmin_vps.cgroup_version == 1
                       '/sys/fs/cgroup/pids/lxc.payload.vps/pids.current'
                     else
                       '/sys/fs/cgroup/lxc.payload.vps/pids.current'
                     end
      end

      begin
        st, out, err = vmexec(dom, %w[cat] + cat_files)
      rescue Libvirt::Error => e
        log(:warn, "Error occurred while reading stats from VPS #{vpsadmin_vps.id}: #{e.message}")
        return
      end

      if st != 0
        log(:warn, "Reading status from VPS #{vpsadmin_vps.id} exited with #{st}: #{err.inspect}")
      end

      uptime_data, loadavg_data, nproc_cg = out.strip.split("\n")

      begin
        vpsadmin_vps.uptime = SystemProbes::Uptime.new(uptime_data || '').uptime
      rescue ParserError
        # pass
      end

      begin
        vpsadmin_vps.loadavg = SystemProbes::LoadAvg.new(loadavg_data || '').avg
      rescue ParserError
        # pass
      end

      if nproc_cg
        vpsadmin_vps.nproc = nproc_cg.to_i
      else
        _, nproc_sh = vmexec(dom, ['sh', '-c', 'echo /proc/[0-9]* | wc -w'])
        vpsadmin_vps.nproc = nproc_sh.to_i
      end

      update_process_counts(vpsadmin_vps, dom)

      return unless vpsadmin_vps.read_hostname?

      begin
        st, out, =
          if vpsadmin_vps.vm_type == 'qemu_container'
            vmctexec(dom, %w[cat /proc/sys/kernel/hostname])
          else
            vmexec(dom, %w[cat /proc/sys/kernel/hostname])
          end
      rescue Libvirt::Error => e
        log(:warn, "Error occurred while reading hostname from VPS #{vpsadmin_vps.id}: #{e.message}")
        return
      end

      if st == 0
        vpsadmin_vps.hostname = out.strip
      else
        log(:warn, "Reading hostname from VPS #{vpsadmin_vps.id} exited with #{st}: #{err.inspect}")
        vpsadmin_vps.hostname = 'unable-to-read'
      end
    end

    def update_process_counts(vpsadmin_vps, dom)
      cmd = ['sh', '-c', PROCESS_COUNTS_COMMAND]
      t = Time.now

      st, out, =
        if vpsadmin_vps.vm_type == 'qemu_container'
          vmctexec(dom, cmd)
        else
          vmexec(dom, cmd)
        end

      return if st != 0

      processes = PROCESS_STATES.to_h { |s| [s, 0] }

      out.strip.split("\n").each do |line|
        state, n_str = line.strip.split
        next unless PROCESS_STATES.include?(state)

        processes[state] = n_str.to_i
      end

      NodeBunny.publish_wait(
        @exchange,
        {
          vps_id: vpsadmin_vps.id.to_i,
          time: t.to_i,
          processes:
        }.to_json,
        content_type: 'application/json',
        routing_key: 'vps_os_processes'
      )
    end

    def report_status(vps, t)
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
  end
end
