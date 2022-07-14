module Transactions::VpsBgp
  class UpdatePeer < ::Transaction
    t_name :vps_bgp_update_peer
    t_type 5502
    queue :vps

    # @param [::VpsBgpPeer] vps_bgp_peer
    # @param [nil, Array<::VpsBgpIpAddress>] override peer IP addresses
    def params(vps_bgp_peer, ip_addresses: nil)
      self.vps_id = vps_bgp_peer.vps.id
      self.node_id = vps_bgp_peer.vps.node_id

      bgp_ips = ip_addresses || vps_bgp_peer.vps_bgp_ip_addresses.where.not(
        confirmed: ::VpsBgpIpAddress.confirmed(:confirm_destroy),
      )

      {
        pool_fs: vps_bgp_peer.vps.dataset_in_pool.pool.filesystem,
        peer_id: vps_bgp_peer.id,
        host_ip_address: vps_bgp_peer.host_ip_address.ip_addr,
        node_asn: vps_bgp_peer.node_asn,
        vps_asn: vps_bgp_peer.vps_asn,
        protocol: vps_bgp_peer.protocol,
        route_limit: vps_bgp_peer.route_limit,
        enabled: vps_bgp_peer.enabled,
        ip_addresses: bgp_ips.map do |bgp_ip|
          {
            ip_version: bgp_ip.ip_address.version,
            ip_address: bgp_ip.ip_address.to_s,
            priority: bgp_ip.priority,
          }
        end,
      }
    end
  end
end
