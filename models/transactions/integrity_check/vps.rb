module Transactions::IntegrityCheck
  class Vps < ::Transaction
    t_name :integrity_vps
    t_type 6006

    include Utils

    def params(check, node)
      @integrity_check = check
      self.t_server = node.id

      {
          vpses: serialize_query(
              ::Vps.includes(:os_template).where(node: node).order('vps_id'),
              nil,
              :add_vps
          ),
          integrity_check_id: check.id
      }
    end

    protected
    def add_vps(vps, obj)
      transaction_chain.lock(vps)

      {
          vps_id: vps.id,
          status: vps.running?,
          hostname: vps.hostname,
          os_template: vps.os_template.name,
          memory: vps.memory,
          swap: vps.swap,
          cpu: vps.cpu,
          ip_addresses: serialize_query(
              vps.ip_addresses,
              obj,
              :add_ip
          )
      }
    end

    def add_ip(ip, obj)
      transaction_chain.lock(ip)

      {
          addr: ip.addr,
          version: ip.version
      }
    end
  end
end
