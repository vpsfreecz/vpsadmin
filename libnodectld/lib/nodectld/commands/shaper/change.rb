module NodeCtld
  class Commands::Shaper::Change < Commands::Base
    handle 2009

    def exec
      Shaper.update_ip(
        @vps_id,
        netif: @veth_name,
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
      Shaper.update_ip(
        @vps_id,
        netif: @veth_name,
        addr: @addr,
        prefix: @prefix,
        version: @version,
        class_id: @shaper_original['class_id'],
        max_tx: @shaper_original['max_tx'],
        max_rx: @shaper_original['max_rx'],
      )
      ok
    end
  end
end
