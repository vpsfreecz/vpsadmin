module VpsAdmind
  class Commands::Firewall::RegIp < Commands::Base
    handle 2014

    def exec
      Firewall.new.reg_ip(@addr, @version)
      ok
    end

    def rollback
      Firewall.new.unreg_ip(@addr, @version)
      ok
    end
  end
end
