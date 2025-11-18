module NodeCtld
  class Commands::Vps::RescueEnter < Commands::Base
    handle 2037
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
          rescuefs: {
            type: @rescue_volume['format'],
            path: File.join(@rescue_volume['pool_path'], "#{@rescue_volume['name']}.#{@rescue_volume['format']}"),
            serial: "vpsadmin-volume-#{@rescue_volume['id']}"
          },
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
      cfg.arch = @arch
      cfg.variant = @variant
      cfg.hostname = @hostname
      cfg.rootfs_label = @rootfs_volume['label']
      cfg.rescue_label = @rescue_volume['label']
      cfg.rescue_rootfs_mountpoint = @rescue_rootfs_mountpoint
      cfg.save

      ConfigDrive.create(@vps_id, cfg)

      add_rescue_warnings

      ok
    end

    def rollback
      ok
    end

    protected

    def add_rescue_warnings
      vol_path = File.join(
        @rescue_volume['pool_path'],
        "#{@rescue_volume['name']}.#{@rescue_volume['format']}"
      )

      NbdAllocator.with_device do |nbd_dev|
        syscmd("qemu-nbd --connect #{nbd_dev} #{vol_path}")

        mountpoint = Dir.mktmpdir("vpsadmin-vol-#{@rescue_volume['name']}-")

        syscmd("mount #{nbd_dev} #{mountpoint}")

        pid = Process.fork do
          sys = OsCtl::Lib::Sys.new
          sys.chroot(mountpoint)

          write_files
        end

        Process.wait(pid)

        if $?.exitstatus != 0
          log(:warn, "Rescue system modification process exited with #{$?.exitstatus}")
        end

        syscmd("umount #{mountpoint}", valid_rcs: :all)
        Dir.rmdir(mountpoint)

        syscmd("qemu-nbd --disconnect #{nbd_dev}")
      end
    end

    def write_files
      return unless File.exist?('/etc/profile')

      # Set login message
      File.open('/etc/motd', 'w') do |f|
        f.write(<<~END)




          *****************************************************************
          *                      VPS in rescue mode!                      *
          *****************************************************************


          The rescue system is temporary and will be destroyed when the VPS
          resumes normal operation. Backup any data that you wish to preserve.
        END

        if @rescue_rootfs_mountpoint
          f.write(<<~END)

            Root file system of VPS #{@vps_id} is mounted to "#{@rescue_rootfs_mountpoint}".
          END
        end

        f.write("\n\n")
      end

      # Customize shell prompt
      ['/etc/profile', '/root/.profile'].each do |profile|
        File.open(profile, 'a') do |f|
          f.puts(<<~END)

            # vpsAdmin rescue mode
            PS1="\n[VPS in rescue mode]\n$PS1"
          END
        end

        break
      rescue SystemCallError
        next
      end
    end
  end
end
