require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::MfaFactorChange < Operations::Base
    # Serialize factor changes with authentication. When +revoke_recovery+ is
    # set, recovery rows are locked before the factor to preserve the global
    # user -> authority -> factor lock order.
    def run(factor, revoke_recovery: false)
      factor.class.transaction do
        user = factor.user
        user.lock!
        recoveries =
          if revoke_recovery
            ::PasswordRecovery.active_verified_with(factor).order(:id).lock.to_a
          else
            []
          end
        locked_factor = factor.class.where(
          id: factor.id,
          user_id: user.id
        ).lock.take!

        result = yield(locked_factor, user)
        unless recoveries.empty?
          now = Time.current
          recoveries.each { |recovery| recovery.update!(invalidated_at: now) }
        end
        result
      end
    end
  end
end
