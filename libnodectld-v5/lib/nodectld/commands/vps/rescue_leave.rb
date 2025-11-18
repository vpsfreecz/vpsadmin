module NodeCtld
  class Commands::Vps::RescueLeave < Commands::Base
    handle 2038
    needs :system

    def exec
      conn = LibvirtClient.new

      cfg = VpsConfig.open(@vps_id)

      cmdline = [
        'root=PARTUUID=fac0aeec-7358-4d5c-a3aa-ba899b14a17f',
        'ro',
        'console=hvc0',
        'quiet',
        "vpsadmin.cgroupv=#{@cgroup_version}"
      ]

      xml = ErbTemplate.render(
        "libvirt/#{@vm_type}.xml",
        {
          name: @vps_id.to_s,
          uuid: @uuid,
          qemu: '/run/current-system/sw/bin/qemu-system-x86_64',
          cpu: @cpu,
          memory: @memory,
          kernel_path: '/run/nodectl/managed-vm/kernel',
          kernel_cmdline: cmdline.join(' '),
          stage2_type: 'qcow2',
          stage2_path: '/run/nodectl/managed-vm/stage-2',
          config_path: File.join($CFG.get(:vpsadmin, :config_drive_dir), "#{@vps_id}.iso"),
          rootfs: {
            type: @rootfs_volume['format'],
            path: File.join(@rootfs_volume['pool_path'], "#{@rootfs_volume['name']}.#{@rootfs_volume['format']}"),
            serial: "vpsadmin-volume-#{@rootfs_volume['id']}"
          },
          rescuefs: nil,
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

      puts xml

      dom = conn.define_domain_xml(xml)

      cfg.vm_type = @vm_type
      cfg.os = @os
      cfg.os_family = @os_family
      cfg.console_port = @console_port
      cfg.distribution = @distribution
      cfg.version = @version
      cfg.hostname = @hostname
      cfg.rootfs_label = @rootfs_volume['label']
      cfg.rescue_label = nil
      cfg.rescue_rootfs_mountpoint = nil
      cfg.save

      ConfigDrive.create(@vps_id, cfg)

      ok
    end

    def rollback
      ok
    end
  end
end
