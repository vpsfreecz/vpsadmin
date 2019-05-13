require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::User::IncompleteLogin < Operations::Base
    # @param auth_token [AuthToken]
    # @param mechanism [:totp]
    # @param reason [String]
    def run(auth_token, mechanism, reason)
      ActiveRecord::Base.transaction do
        ::UserFailedLogin.create!(
          user: auth_token.user,
          auth_type: mechanism,
          reason: reason,
          api_ip_addr: auth_token.api_ip_addr,
          api_ip_ptr: auth_token.api_ip_ptr,
          client_ip_addr: auth_token.client_ip_addr,
          client_ip_ptr: auth_token.client_ip_ptr,
          user_agent: auth_token.user_agent,
          client_version: auth_token.client_version,
        )
        ::User.increment_counter(:failed_login_count, auth_token.user.id)
      end
    end
  end
end
