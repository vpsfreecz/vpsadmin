module Transactions::Node
  class StorePublicKeys < ::Transaction
    t_name :node_store_public_keys
    t_type 6

    def params(node)
      self.node_id = node.id
      {}
    end
  end
end
