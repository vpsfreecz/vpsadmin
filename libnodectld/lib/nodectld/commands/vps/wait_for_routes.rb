module NodeCtld
  class Commands::Vps::WaitForRoutes < Commands::Base
    handle 2026

    def exec
      wait_for_routes if @direction == 'execute'
      ok
    end

    def rollback
      wait_for_routes if @direction == 'rollback'
      ok
    end

    protected
    def wait_for_routes
      RouteCheck.wait(@pool_fs, @vps_id, timeout: @timeout || RouteCheck::TIMEOUT)
    end
  end
end
