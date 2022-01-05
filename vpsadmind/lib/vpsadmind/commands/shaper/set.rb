module VpsAdmind
  class Commands::Shaper::Set < Commands::Base
    handle 2010

    def exec
      Shaper.new.shape_set(@addr, @prefix, @version, @shaper)
      ok
    end

    def rollback
      Shaper.new.shape_unset(@addr, @prefix, @version, @shaper)
      ok
    end
  end
end
