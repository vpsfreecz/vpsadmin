module NodeCtld
  class Commands::Shaper::Unset < Commands::Base
    handle 2011

    def exec
      ok
    end

    def rollback
      ok
    end
  end
end
