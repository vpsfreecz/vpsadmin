module NodeCtld
  class Commands::Utils::NoOp < Commands::Base
    handle 10_001

    def exec
      sleep(@sleep) if @sleep
      ok
    end

    def rollback
      sleep(@sleep) if @sleep
      ok
    end
  end
end
