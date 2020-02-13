module NodeCtld
  class Commands::Vps::SendRollbackConfig < Commands::Base
    handle 3035
    needs :system, :osctl

    def exec
      ok
    end

    def rollback
      osctl(%i(ct del), @vps_id, {force: true})
      ok
    end
  end
end
