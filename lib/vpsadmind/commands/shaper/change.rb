module VpsAdmind
  class Commands::Shaper::Change < Commands::Base
    handle 2009

    def exec
      Shaper.new.shape_change(@addr, @version, @shaper)
      ok
    end
  end
end
