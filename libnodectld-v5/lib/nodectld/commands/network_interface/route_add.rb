module NodeCtld
  class Commands::NetworkInterface::RouteAdd < Commands::Base
    handle 2006
    needs :libvirt, :routes, :vps

    def exec
      wait_for_route_to_clear(@version, @addr, @prefix, timeout: @timeout)
      NetworkInterface.new(domain, @host_name, @guest_name).add_route(
        @addr, @prefix, @version, @register, via: @via
      )
      ok
    end

    def rollback
      NetworkInterface.new(domain, @host_name, @guest_name).del_route(
        @addr, @prefix, @version, @register
      )
      ok
    end
  end
end
