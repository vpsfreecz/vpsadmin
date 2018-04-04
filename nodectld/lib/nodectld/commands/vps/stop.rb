module NodeCtld
  class Commands::Vps::Stop < Commands::Base
    handle 1002
    needs :system

    def exec
      NodeCtld::DelayedMounter.unregister_vps(@vps_id)

      @vps = Vps.new(@vps_id)
      @vps.stop
      ok
    end

    def rollback
      @vps = Vps.new(@vps_id)
      @vps.start
      ok
    end
  end
end
