module NodeCtld
  class Commands::NetworkInterface::SetShaper < Commands::Base
    handle 2031
    needs :system, :libvirt, :vps

    def exec
      NetworkInterface.new(domain, @host_name, @guest_name).set_shaper(@max_tx['new'], @max_rx['new'])
      ok
    end

    def rollback
      NetworkInterface.new(domain, @host_name, @guest_name).set_shaper(@max_tx['original'], @max_rx['original'])
      ok
    end
  end
end
