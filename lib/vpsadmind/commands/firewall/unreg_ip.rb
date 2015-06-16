module VpsAdmind
  class Commands::Firewall::UnregIp < Commands::Base
    handle 2015

    def exec
      Firewall.new.unreg_ip(@addr, @version)
      ok
    end

    def rollback
      Firewall.new.reg_ip(@addr, @version)
      ok
    end
  end
end
