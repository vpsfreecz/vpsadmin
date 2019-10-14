module NodeCtld
  class Commands::Vps::SendSync < Commands::Base
    handle 3032
    needs :system, :osctl

    def exec
      osctl(%i(ct send sync), @vps_id)
    end

    def rollback
      ok
    end
  end
end
