module VpsAdmind
  class Commands::NetworkInterface::HostIpDel < Commands::Base
    handle 2023
    needs :routes

    def exec
      NetworkInterface.new(@vps_id, @interface).del_host_addr(@addr, @prefix)
      ok
    end

    def rollback
      wait_for_route_to_clear(@version, @addr, timeout: @timeout)
      NetworkInterface.new(@vps_id, @interface).add_host_addr(@addr, @prefix)
      ok
    end
  end
end
