module NodeCtld
  class Commands::Vps::Start < Commands::Base
    handle 1001

    def exec
      @vps = Vps.new(@vps_id)
      @vps.start(@start_timeout, @autostart_priority)
    end

    def rollback
      @vps = Vps.new(@vps_id)
      @vps.stop
    end
  end
end
