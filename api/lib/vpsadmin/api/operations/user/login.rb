require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::User::Login < Operations::Base
    # @param user [::User]
    # @param request [Sinatra::Request]
    def run(user, request)
      if user.lockout
        raise Exceptions::OperationError, 'account is locked out'
      end

      ::User.increment_counter(:login_count, user.id)
      user.last_login_at = user.current_login_at
      user.current_login_at = Time.now
      user.last_login_ip = user.current_login_ip
      user.current_login_ip = request.ip
      user.lockout = true if user.password_reset
      user.save!
      ::User.current = user
    end
  end
end
