module VpsAdmind
  class Commands::Network::Register < Commands::Base
    handle 2201
    
    def exec
      VpsAdmind::Firewall.networks.add!(@ip_version, @address, @prefix, @role)
      ok
    end

    def rollback
      VpsAdmind::Firewall.networks.remove!(@ip_version, @address, @prefix, @role)
      ok
    end
  end
end
