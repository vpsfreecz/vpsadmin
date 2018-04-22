module NodeCtld
  class Commands::Shaper::RootChange < Commands::Base
    handle 2012

    def exec
      Shaper.new.root_change(@max_tx, @max_rx)
      ok
    end

    def rollback
      Shaper.new.root_change(@original['max_tx'], @original['max_rx']) if @original
      ok
    end
  end
end
