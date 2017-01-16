module Transactions::Queue
  class Reserve < ::Transaction
    t_name :queue_reserve
    t_type 101
    queue :queue

    # @param node [::Node]
    # @param queue [Symbol]
    def params(node, queue)
      self.node_id = node.id
      {queue: queue}
    end
  end
end
