module VpsAdmind
  class Commands::Vps::Mount < Commands::Base
    handle 5302
    needs :system, :vz, :vps, :zfs, :pool

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
