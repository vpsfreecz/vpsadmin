module NodeCtld
  class Commands::Vps::Boot < Commands::Base
    handle 2029
    needs :system, :osctl, :vps

    def exec
      boot_opts = {
        force: true,
        distribution: @distribution,
        version: @version,
        arch: @arch,
        vendor: @vendor,
        variant: @variant,
        zfs_property: 'refquota=10G',
        wait: @start_timeout || Vps::START_TIMEOUT
      }

      boot_opts[:mount_root_dataset] = @mount_root_dataset if @mount_root_dataset

      osctl(%i[ct boot], @vps_id, boot_opts)

      boot_rootfs = osctl_parse(%i[ct show], [@vps_id])[:boot_rootfs]

      fork_chroot_wait do
        # Some systems setup /etc on the first boot, wait for them a bit
        15.times do
          break if File.exist?('/etc/profile')

          sleep(1)
        end

        # Set login message
        File.open('/etc/motd', 'w') do |f|
          f.write(<<~END)




            *****************************************************************
            *                      VPS in rescue mode!                      *
            *****************************************************************


            The rescue system is temporary and will be destroyed when the VPS
            is rebooted or halted. Backup any data that you wish to preserve.
          END

          if @mount_root_dataset
            f.write(<<~END)

              Root file system of VPS #{@vps_id} is mounted to "#{@mount_root_dataset}".
            END
          end

          f.write("\n\n")
        end

        # Customize shell prompt
        ['/etc/profile', '/root/.profile'].each do |profile|
          File.open(profile, 'a') do |f|
            f.puts(<<~END)

              # vpsAdmin rescue mode
              PS1="[VPS in rescue mode]\n$PS1"
            END
          end

          break
        rescue SystemCallError
          next
        end
      end

      ok
    end

    def rollback
      ok
    end
  end
end
