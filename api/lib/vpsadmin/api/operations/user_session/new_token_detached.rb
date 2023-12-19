require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/user_session/utils'

module VpsAdmin::API
  class Operations::UserSession::NewTokenDetached < Operations::Base
    include Operations::UserSession::Utils

    # @param opts [Hash]
    # @param user [User]
    # @param admin [User]
    # @param request [Sinatra::Request]
    # @param token_lifetime [String]
    # @param token_interval [Integer]
    # @param scope [Array<String>]
    # @param label [String]
    # @return [::UserSession]
    def run(user:, admin:, request:, token_lifetime:, token_interval:, scope:, label:)
      open_session(
        user:,
        request:,
        auth_type: :token,
        scope:,
        generate_token: true,
        token_lifetime:,
        token_interval:,
        admin: admin,
        label: label,
      )
    end
  end
end
