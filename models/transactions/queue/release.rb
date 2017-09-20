module Transactions::Queue
  class Release < ::Transaction
    t_name :queue_release
    t_type 102

    # @param node [::Node]
    # @param queue [Symbol]
    def params(node, queue)
      self.node_id = node.id
      {queue: queue}
    end
  end
end
