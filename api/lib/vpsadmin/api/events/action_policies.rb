require_relative 'action_policies/policy'
require_relative 'action_policies/recording'
require_relative 'action_policies/registry'
require_relative 'action_policies/instrumentation'

HaveAPI::Action.extend(
  VpsAdmin::API::Events::ActionPolicies::PolicyDeclaration
)
