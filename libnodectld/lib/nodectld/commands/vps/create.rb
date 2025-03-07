module NodeCtld
  class Commands::Vps::Create < Commands::Base
    handle 3001
    needs :system, :osctl, :pool

    def exec
      opts = {
        user: @userns_map,
        dataset: File.join(@pool_fs, @dataset_name),
        map_mode: @map_mode,
        distribution: @distribution,
        version: @version,
        arch: @arch,
        variant: @variant,
        vendor: @vendor
      }

      opts[:skip_image] = true if @empty

      osctl_pool(@pool_name, %i[ct create], @vps_id, opts)

      # Some container images can carry their own mounts, e.g. NixOS impermanence.
      # We clear them all so that mounts are managed only through vpsAdmin. If an image
      # requires custom mounts, configure them using OS template config facility.
      osctl_pool(@pool_name, %i[ct mounts clear], @vps_id)

      osctl_pool(@pool_name, %i[ct set hostname], [@vps_id, @hostname]) if @hostname

      # nofile was originally set by osctld automatically, it's not working
      # because of vpsadminos#28. Until it is fixed, we'll set nofile manually.
      osctl_pool(@pool_name, %i[ct prlimits set], [@vps_id, 'nofile', 1024, 1024 * 1024])
      osctl_pool(@pool_name, %i[ct prlimits set], [@vps_id, 'nproc', 128 * 1024, 1024 * 1024])
      osctl_pool(@pool_name, %i[ct prlimits set], [@vps_id, 'memlock', 65_536, 'unlimited'])

      hook_installer = CtHookInstaller.new(@pool_fs, @vps_id)
      hook_installer.install_hooks(%w[veth-up])

      ok
    end

    def rollback
      # TODO: if only the creation fails, osctl cleans up after itself...
      #   so the destroy would fail, because the container does not exist
      call_cmd(Commands::Vps::Destroy, vps_id: @vps_id)
      ok
    end
  end
end
