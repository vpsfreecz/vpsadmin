module NodeCtld
  class Commands::Vps::Reinstall < Commands::Base
    handle 3003
    needs :system, :osctl

    def exec
      osctl(%i[ct reinstall], @vps_id, {
              distribution: @distribution,
              version: @version,
              arch: @arch,
              vendor: @vendor,
              variant: @variant
            })

      # Some container images can carry their own mounts, e.g. NixOS impermanence,
      # which would be applied on reinstall. We can safely remove all mounts,
      # because vpsAdmin-managed mounts are added by hook on VPS start.
      osctl_pool(@pool_name, %i[ct mounts clear], @vps_id)

      ok
    end
  end
end
