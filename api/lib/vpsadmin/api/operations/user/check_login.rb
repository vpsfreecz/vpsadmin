require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::User::CheckLogin < Operations::Base
    include HaveAPI::Hookable

    has_hook :check_login,
             desc: 'Called to check if the user can log in',
             args: { user: '::User', request: 'Sinatra::Request' }

    # @param user [::User]
    # @param request [Sinatra::Request]
    # @raise [Exceptions::OperationError]
    def run(user, request)
      if user.lockout
        raise Exceptions::OperationError,
              'account is locked out, contact support'
      end

      call_hooks_for(:check_login, kwargs: { user:, request: })
      nil
    end
  end
end
