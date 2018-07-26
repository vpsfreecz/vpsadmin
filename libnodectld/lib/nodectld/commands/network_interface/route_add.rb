module NodeCtld
  class Commands::NetworkInterface::RouteAdd < Commands::Base
    handle 2006

    def exec
      NodeCtld::Firewall.ip_map.set(@addr, @prefix, @id, @version, @user_id) if @register
      NetworkInterface.new(@vps_id, @veth_name).add_route(
        @addr, @prefix, @version, @register, @shaper
      )
      ok
    end

    def rollback
      NetworkInterface.new(@vps_id, @veth_name).del_route(
        @addr, @prefix, @version, @register, @shaper
      )
      NodeCtld::Firewall.ip_map.unset(@addr) if @register
      ok
    end
  end
end
