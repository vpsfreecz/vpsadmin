module VpsAdmin::API
  module Operations::UserSession::Utils
    # @param user [::User]
    # @param request [Sinatra::Request]
    # @param auth [:basic, :token]
    # @param token [::SessionToken, nil]
    # @param opts [Hash]
    # @option opts [::User] :admin
    # @return [::UserSession]
    def open_session(user, request, auth, token, opts = {})
      ::UserSession.create!(
        user: user,
        admin: opts[:admin],
        auth_type: auth,
        api_ip_addr: request.ip,
        api_ip_ptr: get_ptr(request.ip),
        client_ip_addr: request.env['HTTP_CLIENT_IP'],
        client_ip_ptr: request.env['HTTP_CLIENT_IP'] && get_ptr(request.env['HTTP_CLIENT_IP']),
        user_session_agent: ::UserSessionAgent.find_or_create!(request.user_agent || ''),
        client_version: request.user_agent || '',
        session_token_id: token && token.id,
        session_token_str: token && token.token,
      )
    end

    # @param ip [String]
    # @return [String]
    def get_ptr(ip)
      Resolv.new.getname(ip)
    rescue Resolv::ResolvError => e
      e.message
    end
  end
end
