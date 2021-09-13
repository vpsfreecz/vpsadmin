module VpsAdmind
  class Commands::Vps::Umount < Commands::Base
    handle 5303
    needs :system, :vz, :vps, :zfs

    def exec
      return ok unless status[:running]

      @vps = Vps.new(@vps_id)
      @vps.restart
      ok
    end

    def rollback
      return ok unless status[:running]

      @vps = Vps.new(@vps_id)
      @vps.restart
      ok
    end
  end
end
