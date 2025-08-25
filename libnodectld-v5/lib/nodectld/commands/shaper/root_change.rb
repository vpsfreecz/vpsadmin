module NodeCtld
  class Commands::Shaper::RootChange < Commands::Base
    handle 2012

    def exec
      return ok unless $CFG.get(:shaper, :enable)

      Shaper.update_root(@max_tx, @max_rx)
      ok
    end

    def rollback
      return ok unless $CFG.get(:shaper, :enable)

      Shaper.update_root(@original['max_tx'], @original['max_rx']) if @original
      ok
    end
  end
end
