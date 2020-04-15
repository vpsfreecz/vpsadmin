module NodeCtld
  class Commands::NetworkInterface::RouteAdd < Commands::Base
    handle 2006
    needs :routes

    def exec
      NodeCtld::Firewall.ip_map.set(@addr, @prefix, @id, @version, @user_id) if @register
      wait_for_route_to_clear(@version, @addr, @prefix, timeout: @timeout)
      NetworkInterface.new(@pool_fs, @vps_id, @veth_name).add_route(
        @addr, @prefix, @version, @register, @shaper, via: @via
      )
      ok
    end

    def rollback
      NetworkInterface.new(@pool_fs, @vps_id, @veth_name).del_route(
        @addr, @prefix, @version, @register, @shaper
      )
      NodeCtld::Firewall.ip_map.unset(@addr) if @register
      ok
    end
  end
end
