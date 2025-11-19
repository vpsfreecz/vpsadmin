module NodeCtld
  class Commands::Vps::DnsResolver < Commands::Base
    handle 2005
    needs :system, :libvirt, :vps

    def exec
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.dns_resolvers = @nameserver

        ConfigDrive.create(@vps_id, cfg)
      end

      distconfig!(domain, ['dns-resolvers-set'] + @nameserver)

      ok
    end

    def rollback
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.dns_resolvers = @original || []

        ConfigDrive.create(@vps_id, cfg)
      end

      distconfig!(domain, ['dns-resolvers-set'] + (@original || []))

      ok
    end
  end
end
