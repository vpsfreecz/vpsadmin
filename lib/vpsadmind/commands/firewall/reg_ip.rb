module VpsAdmind
  class Commands::Firewall::RegIp < Commands::Base
    handle 2014

    def exec
      Firewall.accounting.reg_ip(@addr, @version)
      ok
    end

    def rollback
      Firewall.accounting.unreg_ip(@addr, @version)
      ok
    end
  end
end
