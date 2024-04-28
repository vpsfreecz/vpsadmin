module VpsAdmin::API::Plugins
  module Payments
    module TransactionChains; end
    module Backends; end
  end
end

require_rel 'lib'
require_rel 'models'
require_rel 'resources'

if defined?(namespace)
  # Load tasks only if run by rake
  load_rel 'tasks/*.rake'
end

VpsAdmin::API::Metrics.register_plugin(VpsAdmin::API::Plugins::Payments::Metrics)

VpsAdmin::API::Operations::User::CheckLogin.connect_hook(:check_login) do |ret, user:, **|
  if user.object_state != 'active' && user.user_account && user.user_account.paid_until.nil?
    raise VpsAdmin::API::Exceptions::OperationError,
          'waiting for payment of the membership fee'
  end

  ret
end
