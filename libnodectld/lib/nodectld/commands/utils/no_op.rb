module NodeCtld
  class Commands::Utils::NoOp < Commands::Base
    handle 10001

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
