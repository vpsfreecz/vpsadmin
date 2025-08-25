module NodeCtld
  class Commands::Vps::Start < Commands::Base
    handle 1001

    def exec
      @vps = Vps.new(@vps_id)
      @vps.start(@start_timeout, @autostart_priority)
    end

    def rollback
      if @rollback_start
        @vps = Vps.new(@vps_id)
        @vps.stop
      else
        ok
      end
    end
  end
end
