module NodeCtld
  class Commands::Shaper::Set < Commands::Base
    handle 2010

    def exec
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

    def rollback
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
  end
end
