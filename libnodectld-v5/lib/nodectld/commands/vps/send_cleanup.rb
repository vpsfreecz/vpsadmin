module NodeCtld
  class Commands::Vps::SendCleanup < Commands::Base
    handle 3034
    needs :system, :osctl

    def exec
      osctl(%i[ct send cleanup], @vps_id)
      NetAccounting.remove_vps(@vps_id)
      ok
    end
  end
end
