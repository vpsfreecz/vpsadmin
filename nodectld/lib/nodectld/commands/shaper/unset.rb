module NodeCtld
  class Commands::Shaper::Unset < Commands::Base
    handle 2011

    def exec
      Shaper.new.shape_unset(@addr, @version, @shaper)
      ok
    end

    def rollback
      Shaper.new.shape_set(@addr, @version, @shaper)
      ok
    end
  end
end
