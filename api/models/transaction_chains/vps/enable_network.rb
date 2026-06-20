module TransactionChains
  class Vps::EnableNetwork < ::TransactionChain
    label 'Network'

    # @param vps [::Vps]
    # @param enable [Boolean]
    # @param reason [String]
    def link_chain(vps, enable, reason: '')
      lock(vps)

      vps.network_interfaces.each do |netif|
        use_chain(NetworkInterface::Update, args: [netif, { enable: }])
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.edit(vps, enable_network: enable)
      end

      route_event!(
        enable ? 'vps.network_enabled' : 'vps.network_disabled',
        user: vps.user,
        vps:,
        subject: "VPS ##{vps.id} network #{enable ? 'enabled' : 'disabled'}",
        summary: reason,
        parameters: {
          vps_id: vps.id,
          vps_hostname: vps.hostname,
          reason:
        }
      )
    end
  end
end
