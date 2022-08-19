module NodeCtld
  class Commands::Shaper::Set < Commands::Base
    handle 2010

    def exec
      return ok unless $CFG.get(:shaper, :enable)

      Shaper.add_ip(
        @vps_id,
        interface: @netif,
        addr: @addr,
        prefix: @prefix,
        version: @version,
        class_id: @shaper['class_id'],
        max_tx: @shaper['max_tx'],
        max_rx: @shaper['max_rx'],
      )
      ok
    end

    def rollback
      return ok unless $CFG.get(:shaper, :enable)

      Shaper.remove_ip(
        @vps_id,
        interface: @netif,
        addr: @addr,
        prefix: @prefix,
        version: @version,
        class_id: @shaper['class_id'],
      )
      ok
    end
  end
end
