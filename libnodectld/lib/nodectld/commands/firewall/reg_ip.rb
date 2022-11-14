module NodeCtld
  class Commands::Firewall::RegIp < Commands::Base
    handle 2014

    def exec
      ok
    end

    def rollback
      ok
    end
  end
end
