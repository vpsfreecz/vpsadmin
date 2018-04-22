module NodeCtld
  class Commands::Network::Register < Commands::Base
    handle 2201

    def exec
      NodeCtld::Firewall.networks.add!(@ip_version, @address, @prefix, @role)
      ok
    end

    def rollback
      NodeCtld::Firewall.networks.remove!(@ip_version, @address, @prefix, @role)
      ok
    end
  end
end
