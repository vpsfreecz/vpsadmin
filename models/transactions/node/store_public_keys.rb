module Transactions::Node
  class StorePublicKeys < ::Transaction
    t_name :node_store_public_keys
    t_type 6

    def params(node)
      self.t_server = node.id
      {}
    end
  end
end
