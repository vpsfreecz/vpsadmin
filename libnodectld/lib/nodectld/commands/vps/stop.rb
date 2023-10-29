module NodeCtld
  class Commands::Vps::Stop < Commands::Base
    handle 1002
    needs :system

    def exec
      @vps = Vps.new(@vps_id)
      @vps.stop
      ok
    end

    def rollback
      if @rollback_stop
        @vps = Vps.new(@vps_id)
        @vps.start(@start_timeout, @autostart_priority)
        ok
      else
        ok
      end
    end
  end
end
