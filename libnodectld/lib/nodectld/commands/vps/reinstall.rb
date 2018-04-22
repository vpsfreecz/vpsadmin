module NodeCtld
  class Commands::Vps::Reinstall < Commands::Base
    handle 3003
    needs :system, :osctl

    def exec
      osctl(%i(ct reinstall), @vps_id, {
        distribution: @distribution,
        version: @version,
        arch: @arch,
        vendor: @vendor,
        variant: @variant,
      })
      ok
    end
  end
end
