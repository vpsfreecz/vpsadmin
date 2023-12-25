require 'vpsadmin/api/operations/utils/dns'

module VpsAdmin::API
  module Operations::UserSession::Utils
    include Operations::Utils::Dns

    # @param user [::User]
    # @param request [Sinatra::Request]
    # @param auth [:basic, :token]
    # @param token [::SessionToken, nil]
    # @param scope [Array<String>]
    # @param opts [Hash]
    # @option opts [::User] :admin
    # @return [::UserSession]
    def open_session(user, request, auth, token, scope, opts = {})
      ::UserSession.create!(
        user: user,
        admin: opts[:admin],
        auth_type: auth,
        scope: scope,
        api_ip_addr: request.ip,
        api_ip_ptr: get_ptr(request.ip),
        client_ip_addr: request.env['HTTP_CLIENT_IP'],
        client_ip_ptr: request.env['HTTP_CLIENT_IP'] && get_ptr(request.env['HTTP_CLIENT_IP']),
        user_agent: ::UserAgent.find_or_create!(request.user_agent || ''),
        client_version: request.user_agent || '',
        session_token_id: token && token.id,
        session_token_str: token && token.token,
      )
    end
  end
end
