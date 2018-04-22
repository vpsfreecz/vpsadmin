module NodeCtld
  class Commands::Shaper::Change < Commands::Base
    handle 2009

    def exec
      Shaper.new.shape_change(@addr, @version, @shaper)
      ok
    end

    def rollback
      Shaper.new.shape_change(@addr, @version, @shaper_original)
      ok
    end
  end
end
