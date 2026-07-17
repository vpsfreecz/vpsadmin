require 'digest'
require 'json'

module VpsAdmin::API::KernelEvidence
  module Revision
    module_function

    def collection(node, evidence)
      event_count, event_updated_at = node.node_kernel_events.pick(
        Arel.sql('COUNT(*)'),
        Arel.sql('MAX(updated_at)')
      )
      history_state = node.node_kernel_history_state
      Digest::SHA256.hexdigest(
        JSON.generate([
                        evidence&.snapshot_revision,
                        event_count,
                        event_updated_at&.to_f,
                        history_state&.updated_at&.to_f
                      ])
      )
    end

    def event(event)
      Digest::SHA256.hexdigest(
        JSON.generate([
                        event.id,
                        event.updated_at&.to_f,
                        event.kernel_evidence&.snapshot_revision
                      ])
      )
    end
  end
end
