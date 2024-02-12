require 'vpsadmin/api/operations/utils/dns'

module VpsAdmin::API
  module Operations::UserSession::Utils
    include Operations::Utils::Dns

    # @param user [::User]
    # @param request [Sinatra::Request]
    # @param auth_type [:basic, :token]
    # @param scope [Array<String>]
    # @param generate_token [Boolean]
    # @param token_lifetime [String]
    # @param token_interval [String]
    # @param admin [::User]
    # @return [::UserSession]
    def open_session(user:, request:, auth_type:, scope:, generate_token:, token_lifetime: 'fixed', token_interval: nil, admin: nil, label: nil)
      user_session = ::UserSession.new(
        user:,
        admin:,
        auth_type:,
        scope:,
        api_ip_addr: request.ip,
        api_ip_ptr: get_ptr(request.ip),
        client_ip_addr: request.env['HTTP_CLIENT_IP'],
        client_ip_ptr: request.env['HTTP_CLIENT_IP'] && get_ptr(request.env['HTTP_CLIENT_IP']),
        user_agent: ::UserAgent.find_or_create!(request.user_agent || ''),
        client_version: request.user_agent || '',
        token_lifetime:,
        token_interval:,
        label: label || request.user_agent
      )

      if generate_token
        if token_lifetime != 'permanent' && token_interval.nil?
          raise ArgumentError, 'missing token_interval for non-permanent token_lifetime'
        end

        valid_to = token_lifetime == 'permanent' ? nil : Time.now + token_interval

        ::Token.for_new_record!(valid_to) do |token|
          user_session.token = token
          user_session.token_str = token.token
          user_session.save!
          user_session
        end
      end

      user_session
    end
  end
end
