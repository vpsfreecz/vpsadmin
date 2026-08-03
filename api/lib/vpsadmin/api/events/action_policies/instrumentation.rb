module VpsAdmin::API::Events::ActionPolicies
  module ActionExecution
    def safe_exec
      policies = VpsAdmin::API::Events::ActionPolicies
      policy = policies.for(self.class)

      if policy&.records_transaction_chain_resources?
        recorder = VpsAdmin::API::Events::ActionPolicies::Recorder.new(policy)
        response = policies.with_recorder(recorder) { super }

        recorder.emit! if recorder.pending?

        return response
      end

      return super unless policy&.records_resources?

      recorder = VpsAdmin::API::Events::ActionPolicies::Recorder.new(policy)
      response = nil

      if policy.atomic
        ::ApplicationRecord.transaction(requires_new: true) do
          VpsAdmin::API::Events::ActionPolicies.with_recorder(recorder) do
            response = super
          end

          raise ::ActiveRecord::Rollback unless response.first

          recorder.emit!
        end
      else
        begin
          VpsAdmin::API::Events::ActionPolicies.with_recorder(recorder) do
            response = super
          end
        ensure
          if policy.emit_on_failure && (response.nil? || !response.first)
            recorder.emit!
          end
        end
        recorder.emit! if response&.first
      end

      response
    end
  end

  module OperationExecution
    def run(*args, **kwargs)
      policies = VpsAdmin::API::Events::ActionPolicies
      policy = policies.for_operation(self)

      raise "missing event policy for operation #{name}" unless policy

      policies.capture(policy) { super(*args, **kwargs) }
    end
  end

  module ExternalPolicyExecution
    module_function

    def build(owner, method_owner: owner, mappings: owner.external_event_policy_methods)
      validate!(owner, method_owner, mappings)
      normalized_mappings = mappings.to_h do |method_name, policy_name|
        [method_name.to_sym, policy_name.to_s.dup.freeze]
      end.freeze

      Module.new do
        define_singleton_method(:external_event_policy_methods) { normalized_mappings }

        normalized_mappings.each do |method_name, policy_name|
          define_method(method_name) do |*args, **kwargs, &block|
            policies = VpsAdmin::API::Events::ActionPolicies

            policies.capture(policies.external_policy(policy_name)) do
              super(*args, **kwargs, &block)
            end
          end
        end
      end
    end

    def validate!(owner, method_owner, mappings)
      unless mappings.is_a?(Hash) && mappings.any?
        raise ArgumentError, "#{owner} must declare external event policy methods"
      end

      method_names = mappings.keys.map(&:to_sym)
      if method_names.uniq.length != mappings.length
        raise ArgumentError, "#{owner} declares duplicate external event policy methods"
      end

      policy_names = mappings.values.map(&:to_s)
      if policy_names.uniq.length != mappings.length
        raise ArgumentError, "#{owner} declares duplicate external event policies"
      end

      missing_methods = method_names.reject { |name| method_owner.method_defined?(name) }
      if missing_methods.any?
        raise ArgumentError,
              "#{owner} does not implement external event methods #{missing_methods.join(', ')}"
      end

      policies = VpsAdmin::API::Events::ActionPolicies
      missing_policies = policy_names.reject do |name|
        policies.external_policies.has_key?(name)
      end
      return if missing_policies.empty?

      raise ArgumentError,
            "#{owner} has undeclared external event policies #{missing_policies.join(', ')}"
    end
  end
end
