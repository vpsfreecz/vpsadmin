module NodeCtld
  class Commands::Vps::Create < Commands::Base
    handle 3001
    needs :system

    def exec
      conn = LibvirtClient.new

      xml = ErbTemplate.render(
        "libvirt/#{@vm_type}.xml",
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
          rootfs_serial: "vpsadmin-volume-#{@rootfs_volume['id']}",
          console_port: @console_port,
          network_interfaces: []
        }
      )

      puts xml

      dom = conn.define_domain_xml(xml)

      VpsConfig.create_or_replace(@vps_id) do |cfg|
        cfg.uuid = @uuid
        cfg.vm_type = @vm_type
        cfg.os = @os
        cfg.os_family = @os_family
        cfg.console_port = @console_port
        cfg.distribution = @distribution
        cfg.version = @version
        cfg.hostname = @hostname
        cfg.rootfs_label = @rootfs_volume['label']

        ConfigDrive.create(@vps_id, cfg)
      end

      syscmd("consolectl start #{@vps_id} #{@console_port}")

      ok
    end

    def rollback
      call_cmd(Commands::Vps::Destroy, vps_id: @vps_id, uuid: @uuid)
      ok
    end
  end
end
