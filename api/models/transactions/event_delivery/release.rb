module Transactions::EventDelivery
  class Notify < ::Transaction
    t_name :event_delivery_notify
    t_type 9002
    queue :general
    keep_going

    def params(node_id, deliveries)
      self.node_id = node_id.respond_to?(:id) ? node_id.id : node_id

      ids = Array(deliveries)
            .map { |v| v.respond_to?(:id) ? v.id : v }
            .map(&:to_i)
            .uniq

      { delivery_ids: ids }
    end
  end

  Release = Notify
end
