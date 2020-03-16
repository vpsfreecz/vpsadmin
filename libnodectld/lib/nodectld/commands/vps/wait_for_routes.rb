module NodeCtld
  class Commands::Vps::WaitForRoutes < Commands::Base
    handle 2026

    def exec
      RouteCheck.wait(@pool_fs, @vps_id, timeout: @timeout || RouteCheck::TIMEOUT)
      ok
    end

    def rollback
      ok
    end
  end
end
