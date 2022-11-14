module NodeCtld
  class Commands::Network::Register < Commands::Base
    handle 2201

    def exec
      ok
    end

    def rollback
      ok
    end
  end
end
