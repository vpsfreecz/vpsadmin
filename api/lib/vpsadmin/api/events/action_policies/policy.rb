module VpsAdmin::API::Events::ActionPolicies
  MUTATING_HTTP_METHODS = %i[delete patch post put].freeze
  POLICY_KINDS = %i[
    domain_event
    internal_state
    read
    resource
    runtime_state
    transaction_chain
  ].freeze
  RESOURCE_POLICY_KINDS = %i[resource transaction_chain].freeze
  RESOURCE_ACTIONS = %i[created deleted updated].freeze

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
      kind = normalize_kind(kind)
      validate_models!(kind, models)
      validate_boolean!(:atomic, atomic)
      validate_boolean!(:emit_on_failure, emit_on_failure)
      validate_options!(kind, atomic, emit_on_failure, resource_action)

      attributes = {
        kind:,
        models:,
        reason:,
        atomic:,
        emit_on_failure:,
        resource_action:
      }
      super(**attributes)
    end

    def records_resources?
      kind == :resource
    end

    def records_transaction_chain_resources?
      kind == :transaction_chain && (models == :all || models.any?)
    end

    private

    def normalize_kind(kind)
      normalized = kind.to_sym
      return normalized if POLICY_KINDS.include?(normalized)

      raise ArgumentError,
            "unsupported event policy kind #{kind.inspect}; " \
            "expected one of #{POLICY_KINDS.join(', ')}"
    rescue NoMethodError
      raise ArgumentError,
            "unsupported event policy kind #{kind.inspect}; " \
            "expected one of #{POLICY_KINDS.join(', ')}"
    end

    def validate_models!(kind, models)
      unless models == :all || models.is_a?(Array)
        raise ArgumentError, 'event policy models must be an array or :all'
      end

      if kind == :resource && models != :all && models.empty?
        raise ArgumentError, 'resource event policy requires at least one model'
      end

      return if RESOURCE_POLICY_KINDS.include?(kind)
      return if models.is_a?(Array) && models.empty?

      raise ArgumentError, "#{kind} event policy does not capture models"
    end

    def validate_boolean!(name, value)
      return if [true, false].include?(value)

      raise ArgumentError, "event policy #{name} must be true or false"
    end

    def validate_options!(kind, atomic, emit_on_failure, resource_action)
      if kind != :resource && atomic
        raise ArgumentError, "#{kind} event policy must be non-atomic"
      end

      if emit_on_failure && (kind != :resource || atomic)
        raise ArgumentError,
              'emit_on_failure requires a non-atomic resource event policy'
      end

      return if resource_action.nil?
      if kind == :transaction_chain && RESOURCE_ACTIONS.include?(resource_action)
        return
      end

      raise ArgumentError,
            'resource_action is supported only for transaction-chain policies ' \
            "and must be one of #{RESOURCE_ACTIONS.join(', ')}"
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
