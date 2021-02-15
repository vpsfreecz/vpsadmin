module NodeCtld
  class Commands::Vps::Boot < Commands::Base
    handle 2029
    needs :system, :osctl

    def exec
      boot_opts = {
        force: true,
        distribution: @distribution,
        version: @version,
        arch: @arch,
        vendor: @vendor,
        variant: @variant,
        zfs_property: 'refquota=10G',
      }

      if @mount_root_dataset
        boot_opts[:mount_root_dataset] = @mount_root_dataset
      end

      osctl(%i(ct boot), @vps_id, boot_opts)
    end

    def rollback
      ok
    end
  end
end
