module NodeCtld
  class Commands::Vps::Start < Commands::Base
    handle 1001
    needs :vps

    def exec
      vps.start(autostart_priority: @autostart_priority)
      ok
    end

    def rollback
      if @rollback_start
        vps.stop
      end

      ok
    end
  end
end
