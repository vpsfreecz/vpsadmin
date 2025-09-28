module TransactionChains
  class NetworkInterface::Veth::Base < ::TransactionChain
    protected

    # @param vps [::Vps]
    # @param type [String]
    # @param name [String]
    def create_netif(vps, type, name)
      ::NetworkInterface.create!(
        vps:,
        kind: type,
        name:,
        host_mac_address: MacAddress.generate!,
        guest_mac_address: MacAddress.generate!
      )
    end

    # @param src_netif [::NetworkInterface]
    # @param dst_vps [::Vps]
    def clone_netif(src_netif, dst_vps)
      ::NetworkInterface.create!(
        vps: dst_vps,
        kind: src_netif.kind,
        name: src_netif.name,
        host_mac_address: MacAddress.generate!,
        guest_mac_address: MacAddress.generate!,
        max_tx: src_netif.max_tx,
        max_rx: src_netif.max_rx,
        enable: src_netif.enable
      )
    end
  end
end
