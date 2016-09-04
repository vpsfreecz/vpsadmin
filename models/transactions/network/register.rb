module Transactions::Network
  class Register < ::Transaction
    t_name :network_register
    t_type 2201

    def params(node, net)
      self.t_server = node.id
      {
          ip_version: net.ip_version,
          address: net.address,
          prefix: net.prefix,
          role: ::Network.roles[net.role],
      }
    end
  end
end
