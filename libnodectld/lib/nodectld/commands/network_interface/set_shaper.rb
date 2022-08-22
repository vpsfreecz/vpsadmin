module NodeCtld
  class Commands::NetworkInterface::SetShaper < Commands::Base
    handle 2031
    needs :system, :osctl, :vps

    def exec
      osctl(
        %i(ct netif set),
        [@vps_id, @veth_name],
        {
          max_tx: @max_tx && @max_tx['new'],
          max_rx: @max_rx && @max_rx['new'],
        }.compact,
      )

      ok
    end

    def rollback
      osctl(
        %i(ct netif set),
        [@vps_id, @veth_name],
        {
          max_tx: @max_tx && @max_tx['original'],
          max_rx: @max_rx && @max_rx['original'],
        }.compact,
      )

      ok
    end
  end
end
