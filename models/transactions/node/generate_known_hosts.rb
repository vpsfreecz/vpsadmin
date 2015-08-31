module Transactions::Node
  class GenerateKnownHosts < ::Transaction
    t_name :node_generate_known_hosts
    t_type 5

    def params(node)
      self.t_server = node.id
      {}
    end
  end
end
