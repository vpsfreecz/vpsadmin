module Transactions::Queue
  class Reserve < ::Transaction
    t_name :queue_reserve
    t_type 101
    queue :queue

    # @param node [::Node]
    # @param queue [Symbol]
    def params(node, queue)
      self.t_server = node.id
      {queue: queue}
    end
  end
end
