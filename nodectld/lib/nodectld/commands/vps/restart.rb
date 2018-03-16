module NodeCtld
  class Commands::Vps::Restart < Commands::Base
    handle 1003

    def exec
      NodeCtld::DelayedMounter.unregister_vps(@vps_id)

      @vps = Vps.new(@vps_id)
      @vps.restart
      ok
    end

    def rollback
      ok
    end

    def post_save(db)
      VpsStatus.new([@vps_id]).update
    end
  end
end
