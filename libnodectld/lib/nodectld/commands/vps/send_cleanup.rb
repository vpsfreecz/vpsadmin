module NodeCtld
  class Commands::Vps::SendCleanup < Commands::Base
    handle 3034
    needs :system, :osctl

    def exec
      osctl(%i(ct send cleanup), @vps_id)
    end
  end
end
