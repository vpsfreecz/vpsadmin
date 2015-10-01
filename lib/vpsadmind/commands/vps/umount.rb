module VpsAdmind
  class Commands::Vps::Umount < Commands::Base
    handle 5303
    needs :system, :vz, :vps, :zfs

    def exec
      return ok unless status[:running]
      
      # FIXME: handle @skip_rollback
      Mounter.umount_all(@vps_id, @mounts)
      ok
    end

    def rollback
      if @skip_rollback
        log(:debug, self, 'Skipping rollback of Vps::Umount')
        ok

      else
        call_cmd(Commands::Vps::Mount, {
            :vps_id => @vps_id,
            :mounts => @mounts.reverse,
            :runscripts => false
        })
      end
    end
  end
end
