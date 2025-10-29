module NodeCtld
  class Commands::NetworkInterface::Enable < Commands::Base
    handle 2032
    needs :system, :libvirt, :vps

    def exec
      NetworkInterface.new(domain, @host_name, @guest_name).enable
      ok
    end

    def rollback
      NetworkInterface.new(domain, @host_name, @guest_name).disable
      ok
    end
  end
end
