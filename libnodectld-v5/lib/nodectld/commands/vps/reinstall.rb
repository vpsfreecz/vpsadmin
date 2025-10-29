module NodeCtld
  class Commands::Vps::Reinstall < Commands::Base
    handle 3003
    def exec
      conn = LibvirtClient.new
      cfg = VpsConfig.open(@vps_id)

      xml = ErbTemplate.render(
        'libvirt/domain.xml',
        {
          name: @vps_id.to_s,
          uuid: @uuid,
          qemu: '/run/current-system/sw/bin/qemu-system-x86_64',
          cpu: @cpu,
          memory: @memory,
          kernel_path: '/run/nodectl/managed-vm/kernel',
          kernel_cmdline: "root=PARTUUID=fac0aeec-7358-4d5c-a3aa-ba899b14a17f ro console=hvc0 quiet vpsadmin.cgroupv=#{@cgroup_version}",
          stage2_type: 'qcow2',
          stage2_path: '/run/nodectl/managed-vm/stage-2',
          config_path: File.join($CFG.get(:vpsadmin, :config_drive_dir), "#{@vps_id}.iso"),
          rootfs_type: @rootfs_volume['format'],
          rootfs_path: File.join(@rootfs_volume['pool_path'], "#{@rootfs_volume['name']}.#{@rootfs_volume['format']}"),
          console_port: @console_port,
          network_interfaces: cfg.network_interfaces.map do |netif|
            {
              host_name: netif.host_name,
              guest_mac: netif.guest_mac,
              max_rx: netif.max_rx,
              max_tx: netif.max_tx
            }
          end
        }
      )

      dom = conn.define_domain_xml(xml)

      cfg.distribution = @distribution
      cfg.version = @version
      cfg.save

      ConfigDrive.create(@vps_id, cfg)

      ok
    end
  end
end
