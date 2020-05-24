module NodeCtld
  class Commands::Vps::RecoverCleanup < Commands::Base
    handle 3303
    needs :system, :osctl

    def exec
      cleanup = {}
      cleanup[:cgroups] = true if @cgroups
      cleanup[:network_interfaces] = true if @network_interfaces

      osctl(%i(ct recover cleanup), @vps_id, cleanup)
    end

    def rollback
      ok
    end
  end
end
