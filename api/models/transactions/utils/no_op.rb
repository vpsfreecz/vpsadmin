module Transactions::Utils
  class NoOp < ::Transaction
    t_name :utils_no_op
    t_type 10001

    def params(node_id, sleep: nil)
      self.node_id = node_id

      {sleep: sleep}
    end
  end
end
