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

  module OAuth2Execution
    def handle_get_authorize(**kwargs)
      capture_oauth2('oauth2.authorize_get') { super(**kwargs) }
    end

    def handle_post_authorize(**kwargs)
      capture_oauth2('oauth2.authorize_post') { super(**kwargs) }
    end

    def get_tokens(authorization, sinatra_request)
      capture_oauth2('oauth2.issue_tokens') do
        super(authorization, sinatra_request)
      end
    end

    def refresh_tokens(authorization, sinatra_request)
      capture_oauth2('oauth2.refresh_tokens') do
        super(authorization, sinatra_request)
      end
    end

    def handle_post_revoke(sinatra_request, token, token_type_hint: nil, client: nil)
      capture_oauth2('oauth2.revoke') do
        super(
          sinatra_request,
          token,
          token_type_hint:,
          client:
        )
      end
    end

    protected

    def capture_oauth2(name, &)
      policies = VpsAdmin::API::Events::ActionPolicies
      policies.capture(policies.external_policy(name), &)
    end
  end

  module NotificationCallbackExecution
    def apply_sms_gateway_callback!(*args, **kwargs)
      policies = VpsAdmin::API::Events::ActionPolicies

      policies.capture(
        policies.external_policy('notifications.sms_callback')
      ) { super(*args, **kwargs) }
    end
  end
end
