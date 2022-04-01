require 'libosctl'

module NodeCtld
  module Utils::Vps
    def find_ct(vps_id = nil)
      Ct.new(osctl_parse(%i(ct show), vps_id || @vps_id))
    end

    def ct
      @ct || (@ct = find_ct)
    end

    def status
      find_ct.state
    end

    def honor_state
      before = status
      yield
      after = status

      if before == :running && after != :running
        call_cmd(Commands::Vps::Start, {vps_id: @vps_id})

      elsif before != :running && after == :running
        call_cmd(Commands::Vps::Stop, {vps_id: @vps_id})
      end
    end

    def ct_hook_dir(pool_fs: @pool_fs, vps_id: @vps_id)
      File.join('/', pool_fs, '..', 'hook/ct', vps_id.to_s)
    end

    def fork_chroot_wait(&block)
      rootfs = ct.boot_rootfs

      pid = Process.fork do
        sys = OsCtl::Lib::Sys.new
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
