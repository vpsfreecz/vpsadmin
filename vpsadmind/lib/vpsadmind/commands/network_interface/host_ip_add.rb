module VpsAdmind
  class Commands::NetworkInterface::HostIpAdd < Commands::Base
    handle 2022
    needs :routes

    def exec
      wait_for_route_to_clear(@version, @addr, timeout: @timeout)
      NetworkInterface.new(@vps_id, @interface).add_host_addr(@addr, @prefix)
      ok
    end

    def rollback
      NetworkInterface.new(@vps_id, @interface).del_host_addr(@addr, @prefix)
      ok
    end
  end
end
