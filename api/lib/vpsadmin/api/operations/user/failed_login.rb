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
      ActiveRecord::Base.transaction do
        ::UserFailedLogin.create!(
          user: user,
          auth_type: mechanism,
          reason: reason,
          api_ip_addr: request.ip,
          api_ip_ptr: get_ptr(request.ip),
          client_ip_addr: request.env['HTTP_CLIENT_IP'],
          client_ip_ptr: request.env['HTTP_CLIENT_IP'] && get_ptr(request.env['HTTP_CLIENT_IP']),
          user_agent: ::UserAgent.find_or_create!(request.user_agent || ''),
          client_version: request.user_agent || '',
        )
        ::User.increment_counter(:failed_login_count, user.id)
      end
    end
  end
end
