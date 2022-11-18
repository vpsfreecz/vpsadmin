module NodeCtld
  class Commands::NetworkInterface::RouteDel < Commands::Base
    handle 2007
    needs :osctl, :routes

    def exec
      NetworkInterface.new(@pool_fs, @vps_id, @veth_name).del_route(
        @addr, @prefix, @version, @unregister, @shaper
      )
      ok
    end

    def rollback
      wait_for_route_to_clear(@version, @addr, @prefix, timeout: @timeout)
      NetworkInterface.new(@pool_fs, @vps_id, @veth_name).add_route(
        @addr, @prefix, @version, @unregister, @shaper, via: @via
      )
      ok
    end
  end
end
