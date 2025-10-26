module NodeCtld
  class Commands::Vps::Stop < Commands::Base
    handle 1002
    needs :vps

    def exec
      vps.stop(kill: @kill)
      ok
    end

    def rollback
      vps.start(autostart_priority: @autostart_priority) if @rollback_stop
      ok
    end
  end
end
