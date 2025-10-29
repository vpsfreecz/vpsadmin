module NodeCtld
  class Commands::NetworkInterface::CreateVethRouted < Commands::Base
    handle 2018
    needs :system, :osctl, :vps

    def exec
      conn = LibvirtClient.new
      dom = conn.lookup_domain_by_uuid(@vps_uuid)

      # TODO: handle enable/disable

      xml = ErbTemplate.render(
        'libvirt/network_interface.xml',
        {
          host_name: @host_name,
          guest_mac: @guest_mac,
          max_rx: @max_rx,
          max_tx: @max_tx
        }
      )

      puts xml

      dom.attach_device(xml, Libvirt::Domain::DEVICE_MODIFY_CONFIG)

      VpsConfig.edit(@vps_id) do |cfg|
        cfg.network_interfaces << VpsConfig::NetworkInterface.new(
          host_name: @host_name,
          guest_name: @guest_name,
          host_mac: @host_mac,
          guest_mac: @guest_mac,
          max_tx: @max_tx,
          max_rx: @max_rx
        )

        ConfigDrive.create(@vps_id, cfg)
      end

      NetAccounting.add_netif(@vps_id, @user_id, @netif_id, @name)
      ok
    end

    def rollback
      conn = LibvirtClient.new
      dom = conn.lookup_domain_by_uuid(@vps_uuid)

      xml = <<~END
        <interface type='ethernet'>
          <alias name='#{@host_name}'/>
        </interface>
      END

      dom.detach_device(xml, Libvirt::Domain::DEVICE_MODIFY_CONFIG)

      VpsConfig.edit(@vps_id) do |cfg|
        cfg.network_interfaces.remove(@guest_name)

        ConfigDrive.create(@vps_id, cfg)
      end

      NetAccounting.remove_netif(@vps_id, @netif_id)
      ok
    end
  end
end
