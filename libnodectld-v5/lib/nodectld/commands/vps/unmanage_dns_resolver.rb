module NodeCtld
  class Commands::Vps::UnmanageDnsResolver < Commands::Base
    handle 2027
    needs :system, :libvirt, :vps

    def exec
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.dns_resolvers = []
      end

      distconfig!(domain, ['dns-resolvers-unset'])

      ok
    end

    def rollback
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.dns_resolvers = @original || []
      end

      distconfig!(domain, ['dns-resolvers-set'] + (@original || []))

      ok
    end
  end
end
