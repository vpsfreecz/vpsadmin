module NodeCtld
  class Commands::Shaper::RootChange < Commands::Base
    handle 2012

    def exec
      Shaper.update_root(@max_tx, @max_rx)
      ok
    end

    def rollback
      Shaper.update_root(@original['max_tx'], @original['max_rx']) if @original
      ok
    end
  end
end
