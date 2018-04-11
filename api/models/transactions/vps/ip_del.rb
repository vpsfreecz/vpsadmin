module Transactions::Vps
  class IpDel < ::Transaction
    t_name :vps_ip_del
    t_type 2007
    queue :network

    def params(vps, ip, unregister = true)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      ret = {
          veth_name: vps.veth_name,
          addr: ip.addr,
          version: ip.version,
          unregister: unregister,
          id: ip.id,
          user_id: ip.user_id || vps.user_id,
      }

      if unregister
        ret[:shaper] = {
            class_id: ip.class_id,
            max_tx: ip.max_tx,
            max_rx: ip.max_rx
        }
      end

      ret
    end
  end
end
