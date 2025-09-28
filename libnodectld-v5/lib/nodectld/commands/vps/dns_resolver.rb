module NodeCtld
  class Commands::Vps::DnsResolver < Commands::Base
    handle 2005
    needs :system

    def exec
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.dns_resolvers = @nameservers
      end

      # TODO: run distconfig within the VM

      ok
    end

    def rollback
      VpsConfig.edit(@vps_id) do |cfg|
        cfg.dns_resolvers = @original || nil
      end

      # TODO: run distconfig within the VM

      ok
    end
  end
end
