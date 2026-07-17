module VpsAdmin::API::SystemState
  class Recorder
    def self.call(node:, values:, observed_at:)
      state = node.node_system_states.current.order(id: :desc).first
      if state && Normalizer.same?(state.attributes.symbolize_keys, values)
        state.update!(last_observed_at: observed_at) if state.last_observed_at != observed_at
        return state
      end

      node.node_system_states.current.update_all(current: false, updated_at: Time.current)
      node.node_system_states.create!(
        values.merge(
          first_observed_at: observed_at,
          last_observed_at: observed_at,
          current: true
        )
      )
    end
  end
end
