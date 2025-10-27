module NodeCtld
  class Commands::NetworkInterface::RouteDel < Commands::Base
    handle 2007
    needs :libvirt, :routes, :vps

    def exec
      NetworkInterface.new(domain, @host_name, @guest_name).del_route(
        @addr, @prefix, @version, @unregister
      )
      ok
    end

    def rollback
      wait_for_route_to_clear(@version, @addr, @prefix, timeout: @timeout)
      NetworkInterface.new(domain, @host_name, @guest_name).add_route(
        @addr, @prefix, @version, @unregister, via: @via
      )
      ok
    end
  end
end
