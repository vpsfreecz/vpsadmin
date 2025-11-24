module NodeCtld
  class Commands::Vps::Define < Commands::Base
    handle 2040

    def exec
      conn = LibvirtClient.new

      begin
        domain = conn.lookup_domain_by_uuid(@vps_uuid)
      rescue Libvirt::Error
        # pass
      else
        FileUtils.mkdir_p(backup_dir)
        File.write(backup_path, domain.xml_desc)
      end

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
          uuid: @vps_uuid,
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
          rescuefs: @rescue_volume && {
            type: @rescue_volume['format'],
            path: File.join(@rescue_volume['pool_path'], "#{@rescue_volume['name']}.#{@rescue_volume['format']}"),
            serial: "vpsadmin-volume-#{@rescue_volume['id']}"
          },
          console_port: @console_port,
          network_interfaces: @network_interfaces.map do |netif|
            {
              host_name: netif['host_name'],
              guest_mac: netif['guest_mac'],
              max_rx: netif['max_rx'],
              max_tx: netif['max_tx']
            }
          end
        }
      )

      puts xml

      conn.define_domain_xml(xml)
      conn.close

      ok
    end

    def rollback
      conn = LibvirtClient.new

      if @rollback_undefine
        domain = conn.lookup_domain_by_uuid(@vps_uuid)
        domain.undefine
        conn.close
        return ok
      end

      unless File.exist?(backup_path)
        raise "Backup file at #{backup_path.inspect} not found"
      end

      conn.define_domain_xml(File.read(backup_path))
      conn.close

      ok
    end

    protected

    def backup_dir
      $CFG.get(:vpsadmin, :domain_xml_dir)
    end

    def backup_path
      File.join(backup_dir, "#{@vps_id}.xml.backup")
    end
  end
end
