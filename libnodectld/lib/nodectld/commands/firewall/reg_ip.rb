module NodeCtld
  class Commands::Firewall::RegIp < Commands::Base
    handle 2014

    def exec
      Firewall.ip_map.set(@addr, @prefix, @id, @version, @user_id)
      Firewall.accounting.reg_ip(@addr, @prefix, @version)
      ok
    end

    def rollback
      Firewall.accounting.unreg_ip(@addr, @prefix, @version)
      Firewall.ip_map.unset(@addr)
      ok
    end
  end
end
