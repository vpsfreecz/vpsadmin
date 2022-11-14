module NodeCtld
  class Commands::Firewall::UnregIp < Commands::Base
    handle 2015

    def exec
      ok
    end

    def rollback
      ok
    end
  end
end
