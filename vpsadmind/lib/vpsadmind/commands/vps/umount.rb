module VpsAdmind
  class Commands::Vps::Umount < Commands::Base
    handle 5303
    needs :system, :vz, :vps, :zfs

    def exec
      return ok unless status[:running]
      
      mounter = VpsAdmind::Mounter.new(@vps_id)
      @umounted_mounts = []

      @mounts.each do |m|
        VpsAdmind::DelayedMounter.unregister_vps_mount(@vps_id, m['id'])
        
        mounter.umount(m)
        @umounted_mounts << m
      end

      ok
    end

    def rollback
      mounts = @umounted_mounts || @mounts

      call_cmd(Commands::Vps::Mount, {
          :vps_id => @vps_id,
          :mounts => mounts.reverse
      })
    end
  end
end
