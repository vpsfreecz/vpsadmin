module VpsAdmind
  class Commands::Firewall::RegIp < Commands::Base
    handle 2014

    def exec
      Firewall.ip_map.set(@addr, @id, @version, @user_id)
      Firewall.accounting.reg_ip(@addr, @version)
      ok
    end

    def rollback
      Firewall.accounting.unreg_ip(@addr, @version)
      Firewall.ip_map.unset(@addr)
      ok
    end
  end
end
