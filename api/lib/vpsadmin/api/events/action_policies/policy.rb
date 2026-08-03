module VpsAdmin::API::Events::ActionPolicies
  MUTATING_HTTP_METHODS = %i[delete patch post put].freeze

  Policy = Data.define(
    :kind,
    :models,
    :reason,
    :atomic,
    :emit_on_failure,
    :resource_action
  ) do
    def initialize(
      kind:,
      models:,
      reason:,
      atomic:,
      emit_on_failure: false,
      resource_action: nil
    )
      super
    end

    def records_resources?
      kind == :resource
    end

    def records_transaction_chain_resources?
      kind == :transaction_chain && (models == :all || models.any?)
    end
  end

  module PolicyDeclaration
    def event_policy(
      kind = nil,
      models: [],
      reason: nil,
      atomic: true,
      emit_on_failure: false
    )
      return instance_variable_get(:@event_policy) if kind.nil?

      VpsAdmin::API::Events::ActionPolicies.declare_policy(
        self,
        kind:,
        models:,
        reason:,
        atomic:,
        emit_on_failure:
      )
    end
  end
end
