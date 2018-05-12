module NodeCtld
  class Commands::Shaper::Unset < Commands::Base
    handle 2011

    def exec
      Shaper.remove_ip(
        @vps_id,
        netif: @veth_name,
        addr: @addr,
        prefix: @prefix,
        version: @version,
        class_id: @shaper['class_id'],
      )
      ok
    end

    def rollback
      Shaper.add_ip(
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
  end
end
