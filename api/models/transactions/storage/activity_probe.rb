module Transactions::Storage
  class ActivityProbe < ::Transaction
    t_name :storage_activity_probe
    t_type 5291
    # Older nodes understand this persisted queue and reject the new handle.
    queue :storage
    irreversible
    requires_signature true

    def params(request)
      self.node_id = request.fetch(:node_id)
      request
    end
  end
end
