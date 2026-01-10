module NodeCtld
  class Commands::Vps::Restart < Commands::Base
    handle 1003

    def exec
      @vps = Vps.new(@vps_id)
      @vps.restart(@start_timeout, @autostart_priority, kill: @kill)
      ok
    end

    def rollback
      ok
    end
  end
end
