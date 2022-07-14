module Transactions::VpsBgp
  class CommitPeer < ::Transaction
    t_name :vps_bgp_commit_peer
    t_type 5503
    queue :network

    # @param [::VpsBgpPeer] vps_bgp_peer
    # @param [:rollback, :execute] direction
    def params(vps_bgp_peer, direction)
      unless %i[rollback execute].include?(direction)
        raise ArgumentError, 'invalid direction'
      end

      self.node_id = vps_bgp_peer.vps.node_id
      self.vps_id = vps_bgp_peer.vps_id

      {
        direction: direction
      }
    end
  end
end
