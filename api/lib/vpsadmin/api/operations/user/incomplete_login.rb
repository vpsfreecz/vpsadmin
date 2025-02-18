require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::User::IncompleteLogin < Operations::Base
    # @param auth_token_or_challenge [AuthToken, WebauthnChallenge]
    # @param mechanism [:totp]
    # @param reason [String]
    def run(auth_token_or_challenge, mechanism, reason)
      # The user might no longer exist
      return if auth_token_or_challenge.user.nil?

      ActiveRecord::Base.transaction do
        ::UserFailedLogin.create!(
          user: auth_token_or_challenge.user,
          auth_type: mechanism,
          reason:,
          api_ip_addr: auth_token_or_challenge.api_ip_addr,
          api_ip_ptr: auth_token_or_challenge.api_ip_ptr,
          client_ip_addr: auth_token_or_challenge.client_ip_addr,
          client_ip_ptr: auth_token_or_challenge.client_ip_ptr,
          user_agent: auth_token_or_challenge.user_agent,
          client_version: auth_token_or_challenge.client_version
        )
        ::User.increment_counter(:failed_login_count, auth_token_or_challenge.user.id)
      end
    end
  end
end
