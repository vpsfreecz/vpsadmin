require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::ResetPassword < Operations::Base
    # @param auth_token [AuthToken]
    # @param new_password [String]
    # @return [User]
    def run(auth_token, new_password)
      user = auth_token.user
      user.set_password(new_password)
      user.save!
      auth_token.destroy!
      user
    end
  end
end
