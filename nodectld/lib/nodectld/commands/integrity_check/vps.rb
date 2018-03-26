module NodeCtld
  class Commands::IntegrityCheck::Vps < Commands::Base
    handle 6006
    needs :system, :vps, :integrity

    def exec
      db = Db.new

      db.transaction do |t|
        @real_vpses = load_vpses
        @t = t

        @vpses.each do |vps|
          check_vps(vps)
        end

        # Report remaining VPSes
        @real_vpses.each do |vps|
          state_fact(
              @t,
              create_integrity_object(
                  @t,
                  @integrity_check_id,
                  nil,
                  'Vps'
              ),
              'exists',
              false,
              true,
              :high,
              "VPS #{vps[:veid]} should not exist"
          )
        end
      end

      db.close
      ok
    end

    def rollback
      ok
    end

    protected
    def check_vps(vps)
      real_vps = find_vps(vps['vps_id'])

      # Existence
      state_fact(
          @t,
          vps,
          'exists',
          true,
          !real_vps.nil?,
          :high,
          "VPS #{vps['vps_id']} does not exist"
      )

      return if real_vps.nil?

      # Status
      state_fact(
          @t,
          vps,
          'status',
          vps['status'],
          {
              'running' => true,
              'stopped' => false
          }[ real_vps[:status] ],
          :normal,
          "Status is '#{real_vps[:status]}'"
      )

      # On boot
      state_fact(
          @t,
          vps,
          'onboot',
          vps['status'],
          real_vps[:onboot],
          :normal,
          "Onboot is '#{real_vps[:onboot]}'"
      )

      # Private
      state_fact(
          @t,
          vps,
          'private',
          ve_private(vps['vps_id']),
          real_vps[:private],
          :high,
          "Private is '#{real_vps[:private]}'"
      )

      # Root
      state_fact(
          @t,
          vps,
          'root',
          ve_root(vps['vps_id']),
          real_vps[:root],
          :high,
          "Root is '#{real_vps[:root]}'"
      )

      # Hostname
      state_fact(
          @t,
          vps,
          'hostname',
          vps['hostname'],
          real_vps[:hostname],
          :low,
          "Hostname is '#{real_vps[:hostname]}'"
      )

      # OS template
      state_fact(
          @t,
          vps,
          'os_template',
          vps['os_template'],
          real_vps[:ostemplate],
          :normal,
          "OS template is '#{real_vps[:ostemplate]}'"
      )

      # Memory
      state_fact(
          @t,
          vps,
          'memory',
          vps['memory'],
          real_vps[:physpages][:limit] * 4 / 1024,
          :normal,
          "Memory (physpages) is '#{real_vps[:physpages][:limit] * 4 / 1024}'"
      )

      # Swap
      state_fact(
          @t,
          vps,
          'swap',
          vps['swap'],
          real_vps[:swappages][:limit] * 4 / 1024,
          :normal,
          "Swap (swappages) is '#{real_vps[:swappages][:limit] * 4 / 1024}'"
      )

      # CPUs
      state_fact(
          @t,
          vps,
          'cpu',
          vps['cpu'],
          real_vps[:cpus],
          :normal,
          "CPU is '#{real_vps[:cpus]}'"
      )

      # CPU limit
      state_fact(
          @t,
          vps,
          'cpu',
          vps['cpu'] * 100,
          real_vps[:cpulimit],
          :normal,
          "CPU limit is '#{real_vps[:cpulimit]}'"
      )

      # IP addresses
      ips = vps['ip_addresses']
      real_ips = real_vps[:ip]

      ips.each do |ip|
        check_ip(ip, ips, real_ips)
      end

      # Report remaining IP addresses
      real_ips.each do |ip|
        state_fact(
            @t,
            create_integrity_object(
                @t,
                @integrity_check_id,
                vps,
                'IpAddress'
            ),
            'exists',
            false,
            true,
            :normal,
            "IP address '#{ip}' should not be present"
        )
      end
    end

    def check_ip(ip, ips, real_ips)
      found = nil

      real_ips.each_index do |i|
        if real_ips[i] == ip['addr']
          found = i
          break
        end
      end

      state_fact(
          @t,
          ip,
          'exists',
          true,
          !found.nil?,
          :high,
          "IP address '#{ip['addr']}' is not present"
      )

      return if found.nil?

      real_ips.delete_at(found)
    end

    def find_vps(veid)
      found = nil

      @real_vpses.each_index do |i|
        if @real_vpses[i][:veid] == veid
          found = i
          break
        end
      end

      return nil unless found

      @real_vpses.delete_at(found)
    end

    def load_vpses
      JSON.parse(syscmd(
          "#{$CFG.get(:vz, :vzlist)} -aj -o veid,status,onboot,private,root,"+
          "hostname,ostemplate,physpages,swappages,cpus,cpulimit,ip"
      )[:output], symbolize_names: true)
    end
  end
end
