module Transactions::Utils
  class NoOp < ::Transaction
    t_name :utils_no_op
    t_type 10001

    def params(node_id)
      self.t_server = node_id

      {}
    end
  end
end
