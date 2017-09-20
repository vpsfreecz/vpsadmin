module VpsAdmind
  class Commands::Vps::Stop < Commands::Base
    handle 1002
    needs :system, :vz

    def exec
      VpsAdmind::DelayedMounter.unregister_vps(@vps_id)

      @vps = Vps.new(@vps_id)
      @vps.stop

      # Ensure that the VPS is stopped and unmounted, which may not be the case.
      # Vps.stop uses method +try_hard+, so if the VPS cannot be unmounted,
      # the first attempt fails. However, the second attempt succeeds, because
      # the VPS is no longer running and vzctl will not try to unmount it.
      sleep(1)
      st = @vps.status
      if st[:mounted]
        try_harder do
          sleep(3)
          vzctl(:umount, @vps_id)
        end
      end

      ok
    end

    def rollback
      @vps = Vps.new(@vps_id)
      @vps.start
    end

    def post_save(db)
      VpsStatus.new([@vps_id]).update
    end
  end
end
