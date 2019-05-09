require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/user_session/utils'

module VpsAdmin::API
  class Operations::UserSession::NewTokenDetached < Operations::Base
    include Operations::UserSession::Utils

    # @param opts [Hash]
    # @option opts [User] :user
    # @option opts [User] :admin
    # @option opts [Sinatra::Request] :request
    # @option opts [String] :lifetime
    # @option opts [Integer] :interval
    # @option opts [String] :label
    # @return [::UserSession]
    def run(opts)
      token = ::SessionToken.custom!(
        user: opts[:user],
        lifetime: opts[:lifetime],
        interval: opts[:interval],
        label: opts[:label] || request.user_agent,
      )

      open_session(opts[:user], opts[:request], :token, token, admin: opts[:admin])
    end
  end
end
