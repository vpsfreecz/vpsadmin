module Transactions::Utils
  class NoOp < ::Transaction
    t_name :utils_no_op
    t_type 10_001

    def params(node_id, sleep: nil, result_events: nil)
      self.node_id = node_id

      {
        sleep:,
        result_events:
      }.compact
    end
  end
end
