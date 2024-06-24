require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/utils/dns'

module VpsAdmin::API
  class Operations::User::FailedLogin < Operations::Base
    include Operations::Utils::Dns

    # @param user [::User]
    # @param mechanism [:password, :totp]
    # @param reason [String]
    # @param request [Sinatra::Request]
    def run(user, mechanism, reason, request)
      api_ip_addr = request.ip
      api_ip_ptr = get_ptr(api_ip_addr)

      client_ip_addr = request.env['HTTP_CLIENT_IP'] || request.env['HTTP_X_REAL_IP'] || api_ip_addr
      client_ip_ptr = client_ip_addr == api_ip_addr ? api_ip_ptr : get_ptr(client_ip_addr)

      ActiveRecord::Base.transaction do
        ::UserFailedLogin.create!(
          user:,
          auth_type: mechanism,
          reason:,
          api_ip_addr:,
          api_ip_ptr:,
          client_ip_addr:,
          client_ip_ptr:,
          user_agent: ::UserAgent.find_or_create!(request.user_agent || ''),
          client_version: request.user_agent || ''
        )
        ::User.increment_counter(:failed_login_count, user.id)
      end
    end
  end
end
