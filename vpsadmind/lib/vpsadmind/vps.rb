require 'erb'
require 'tempfile'
require 'fileutils'

module VpsAdmind
  class Vps
    include Utils::Log
    include Utils::System
    include Utils::Vz
    include Utils::Zfs

    def initialize(veid)
      @veid = veid
    end

    def start
      try_harder do
        vzctl(:start, @veid, {}, false, [32,])
        vzctl(:set, @veid, {:onboot => "yes"}, true)
      end
    end

    def stop(params = {})
      try_harder do
        vzctl(
            :stop,
            @veid,
            {},
            false,
            params[:force] ? [5, 66] : [],
            timeout: $CFG.get(:vps, :stop_timeout),
            on_timeout: ->(io) { Process.kill('TERM', io.pid) },
        )
        vzctl(:set, @veid, {:onboot => "no"}, true)
      end
    end

    def restart
      vzctl(
          :restart,
          @veid,
          {},
          false,
          [],
          timeout: $CFG.get(:vps, :stop_timeout),
          on_timeout: ->(io) { Process.kill('TERM', io.pid) },
      )
      vzctl(:set, @veid, {:onboot => "yes"}, true)
    end

    def suspend
      acquire_lock do
        unless File.exists?("#{ve_private}/sbin/iptables-save")
          File.symlink("/bin/true", "#{ve_private}/sbin/iptables-save")
          del = true
        end

        vzctl(:suspend, @veid, {:dumpfile => dumpfile})

        File.delete("#{ve_private}/sbin/iptables-save") if del
      end
    end

    def resume
      acquire_lock do
        unless File.exists?("#{ve_private}/sbin/iptables-restore")
          File.symlink("/bin/true", "#{ve_private}/sbin/iptables-restore")
          del = true
        end

        vzctl(:resume, @veid, {:dumpfile => dumpfile})

        File.delete("#{ve_private}/sbin/iptables-restore") if del
      end
    end

    def set_params(params)
      vzctl(:set, @veid, params, true)
    end

    def route_add(addr, v, register, shaper)
      if register
        Shaper.new.shape_set(addr, v, shaper)
        Firewall.accounting.reg_ip(addr, v)
      end
    end

    def route_del(addr, v, unregister, shaper)
      if unregister
        Shaper.new.shape_unset(addr, v, shaper)
        Firewall.accounting.unreg_ip(addr, v)
      end
    end

    def passwd(user, password)
      vzctl(:set, @veid, {:userpasswd => "#{user}:#{password}"})
    end

    def load_file(file)
      vzctl(:exec, @veid, "cat #{file}")
    end

    def script_mount
      "#{$CFG.get(:vz, :vz_conf)}/conf/#{@veid}.mount"
    end

    def script_umount
      "#{$CFG.get(:vz, :vz_conf)}/conf/#{@veid}.umount"
    end

    def ve_conf
      "#{$CFG.get(:vz, :vz_conf)}/conf/#{@veid}.conf"
    end

    def ve_private
      $CFG.get(:vz, :ve_private).gsub(/%\{veid\}/, @veid.to_s)
    end

    def ve_root
      "#{$CFG.get(:vz, :vz_root)}/root/#{@veid}"
    end

    def dumpfile
      $CFG.get(:vps, :migration, :dumpfile).gsub(/%\{veid\}/, @veid.to_s)
    end

    def status
      stat = vzctl(:status, @veid)[:output].split(" ")[2..-1]
      {:exists => stat[0] == "exist", :mounted => stat[1] == "mounted", :running => stat[2] == "running"}
    end

    def honor_state
      before = status
      yield
      after = status

      if before[:running] && !after[:running]
        start
      elsif !before[:running] && after[:running]
        stop
      end
    end

    def ve_private_ds
      "#{$CFG.get(:vps, :zfs, :root_dataset)}/#{@veid}"
    end
  end
end
