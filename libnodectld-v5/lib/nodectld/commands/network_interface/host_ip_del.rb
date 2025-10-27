module NodeCtld
  class Commands::NetworkInterface::HostIpDel < Commands::Base
    handle 2023
    needs :libvirt, :vps

    def exec
      NetworkInterface.new(domain, @host_name, @guest_name).del_host_addr(@addr, @prefix, @version)
      ok
    end

    def rollback
      NetworkInterface.new(domain, @host_name, @guest_name).add_host_addr(@addr, @prefix, @version)
      ok
    end
  end
end
