module NodeCtld
  class Commands::Vps::Restart < Commands::Base
    handle 1003
    needs :vps

    def exec
      vps.restart(autostart_priority: @autostart_priority)
      ok
    end

    def rollback
      ok
    end
  end
end
