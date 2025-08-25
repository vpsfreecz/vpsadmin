require 'libosctl'

module NodeCtld
  module Utils::Vps
    def find_ct(vps_id = nil)
      Ct.new(osctl_parse(%i[ct show], vps_id || @vps_id))
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
        osctl(%i[ct start], @vps_id, { wait: NodeCtld::Vps::START_TIMEOUT })

      elsif before != :running && after == :running
        osctl(%i[ct stop], @vps_id)

      else
        ok
      end
    end

    def fork_chroot_wait(rootfs: nil, &block)
      rootfs ||= ct.boot_rootfs

      pid = Process.fork do
        sys = OsCtl::Lib::Sys.new
        sys.chroot(rootfs)
        block.call
      end

      Process.wait(pid)

      raise "subprocess failed with exit status #{$?.exitstatus}" if $?.exitstatus != 0

      $?
    end
  end
end
