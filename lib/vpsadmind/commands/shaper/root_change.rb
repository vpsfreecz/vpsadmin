module VpsAdmind
  class Commands::Shaper::RootChange < Commands::Base
    handle 2012

    def exec
      Shaper.new.root_change(@max_tx, @max_rx)
      ok
    end
  end
end
