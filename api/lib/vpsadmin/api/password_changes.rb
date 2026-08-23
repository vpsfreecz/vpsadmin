require 'resolv'

module VpsAdmin::API
  module PasswordChanges
    SOURCES = %i[
      authenticated
      forced_reset
      recovery
      administrator
      other
    ].freeze

    module ClientInfo
      protected

      def password_change_client_info(request)
        client_ip_addr = request.env['HTTP_X_REAL_IP'].presence || request.ip

        {
          client_ip_addr:,
          client_ip_ptr: resolve_password_change_ptr(client_ip_addr),
          user_agent: ::UserAgent.find_or_create!(request.user_agent.to_s)
        }
      end

      def resolve_password_change_ptr(address)
        Resolv.new.getname(address)
      rescue Resolv::ResolvError
        address
      end
    end
  end
end
