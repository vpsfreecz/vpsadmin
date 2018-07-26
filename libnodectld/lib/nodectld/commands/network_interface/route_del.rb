module NodeCtld
  class Commands::NetworkInterface::RouteDel < Commands::Base
    handle 2007
    needs :osctl

    def exec
      NetworkInterface.new(@vps_id, @veth_name).del_route(
        @addr, @prefix, @version, @unregister, @shaper
      )
      NodeCtld::Firewall.ip_map.unset(@addr) if @unregister
      ok
    end

    def rollback
      NodeCtld::Firewall.ip_map.set(@addr, @prefix, @id, @version, @user_id) if @unregister
      NetworkInterface.new(@vps_id, @veth_name).add_route(
        @addr, @prefix, @version, @unregister, @shaper
      )
      ok
    end
  end
end
