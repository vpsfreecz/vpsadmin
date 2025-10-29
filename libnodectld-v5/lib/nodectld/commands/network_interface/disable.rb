module NodeCtld
  class Commands::NetworkInterface::Disable < Commands::Base
    handle 2033
    needs :system, :libvirt, :vps

    def exec
      NetworkInterface.new(domain, @host_name, @guest_name).disable
      ok
    end

    def rollback
      NetworkInterface.new(domain, @host_name, @guest_name).enable
      ok
    end
  end
end
