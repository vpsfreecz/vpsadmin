module NodeCtld
  class Commands::Firewall::UnregIp < Commands::Base
    handle 2015

    def exec
      Firewall.accounting.unreg_ip(@addr, @prefix, @version)
      Firewall.ip_map.unset(@addr)
      ok
    end

    def rollback
      Firewall.ip_map.set(@addr, @prefix, @id, @version, @user_id)
      Firewall.accounting.reg_ip(@addr, @prefix, @version)
      ok
    end
  end
end
