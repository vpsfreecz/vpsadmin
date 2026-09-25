module Transactions::Storage
  class Inventory < ::Transaction
    t_name :storage_inventory
    t_type 5290
    # Persist the legacy queue so older daemons can reject handle 5290 safely.
    queue :storage
    irreversible
    requires_signature true

    def params(request)
      self.node_id = request.fetch(:node_id)
      request
    end
  end
end
