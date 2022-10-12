module NodeCtld
  class Commands::Vps::Restart < Commands::Base
    handle 1003

    def exec
      NodeCtld::DelayedMounter.unregister_vps(@vps_id)

      @vps = Vps.new(@vps_id)
      @vps.restart(@start_timeout, @autostart_priority)
      ok
    end

    def rollback
      ok
    end
  end
end
