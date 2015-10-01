module VpsAdmind
  class Commands::Vps::Mount < Commands::Base
    handle 5302
    needs :system, :vz, :vps, :zfs, :pool

    def exec
      return ok unless status[:running]
      Mounter.mount_all(@vps_id, @mounts, true)
      ok
    end

    def rollback
      call_cmd(Commands::Vps::Umount, {
          :mounts => @mounts.reverse,
          :runscripts => false,
          :vps_id => @vps_id
      })
    end
  end
end
