module VpsAdmind
  module Utils::Vps
    def action_script(action)
      path = "#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.#{action}.new"

      File.open(path, 'w') do |f|
        f.write(ERB.new(File.new("templates/ve_#{action}.erb").read, 0).result(binding))
      end

      syscmd("#{$CFG.get(:bin, :chmod)} +x #{path}")

      ok
    end

    def runscript(name, script)
      return ok unless script.length > 0

      f = Tempfile.new("vpsadmind_#{name}")
      f.write("#!/bin/sh\n#{script}")
      f.close

      vzctl(:runscript, @vps_id, f.path)
    end

    def ve_root(vps_id = nil)
      "#{$CFG.get(:vz, :vz_root)}/root/#{vps_id || @vps_id}"
    end

    def ve_private(vps_id = nil)
      $CFG.get(:vz, :ve_private).gsub(/%\{veid\}/, (vps_id || @vps_id).to_s)
    end

    def ve_conf
      "#{$CFG.get(:vz, :vz_conf)}/conf/#{@vps_id}.conf"
    end

    def status
      stat = vzctl(:status, @vps_id)[:output].split(" ")[2..-1]
      {
          :exists => stat[0] == 'exist',
          :mounted => stat[1] == 'mounted',
          :running => stat[2] == 'running'
      }
    end

    def honor_state
      before = status
      yield
      after = status

      if before[:running] && !after[:running]
        call_cmd(Commands::Vps::Start, {:vps_id => @vps_id})

      elsif !before[:running] && after[:running]
        call_cmd(Commands::Vps::Stop, {:vps_id => @vps_id})
      end
    end

    def fork_chroot_wait(&block)
      rootfs = ve_private

      pid = Process.fork do
        sys = VpsAdmind::Sys.new
        sys.chroot(rootfs)
        block.call
      end

      Process.wait(pid)

      if $?.exitstatus != 0
        fail "subprocess failed with exit status #{$?.exitstatus}"
      end

      $?
    end
  end
end
