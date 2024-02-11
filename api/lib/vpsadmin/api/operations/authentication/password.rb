require 'vpsadmin/api/operations/base'
require 'vpsadmin/api/operations/utils/dns'

module VpsAdmin::API
  class Operations::Authentication::Password < Operations::Base
    Result = Struct.new(:user, :authenticated, :complete, :reset_password, :token) do
      alias_method :authenticated?, :authenticated
      alias_method :complete?, :complete
      alias_method :reset_password?, :reset_password
    end

    include Operations::Utils::Dns

    # @param username [String]
    # @param password [String]
    # @param multi_factor [Boolean]
    # @param request [Sinatra::Request]
    # @return [Result, nil]
    def run(username, password, multi_factor: true, request: nil)
      user = ::User.unscoped.where(
        object_state: [
          ::User.object_states[:active],
          ::User.object_states[:suspended]
        ]
      ).find_by('login = ? COLLATE utf8_bin', username)
      return unless user

      provider = CryptoProviders.provider(user.password_version)
      authenticated = provider.matches?(user.password, user.login, password)

      if authenticated
        if CryptoProviders.update?(user.password_version)
          CryptoProviders.current do |name, provider|
            user.update!(
              password_version: name,
              password: provider.encrypt(user.login, password)
            )
          end
        end

        require_totp = require_totp?(user)

        ret = Result.new(
          user,
          authenticated,
          !require_totp,
          !require_totp && user.password_reset
        )

        if require_totp && multi_factor
          ret.token = create_auth_token('totp', user, request)
        elsif user.password_reset && multi_factor
          ret.token = create_auth_token('reset_password', user, request)
        end

        ret
      else
        Result.new(
          user,
          false,
          false,
          false
        )
      end
    end

    protected

    def require_totp?(user)
      user.user_totp_devices.where(enabled: true).any?
    end

    def create_auth_token(purpose, user, request)
      ::Token.for_new_record!(Time.now + (60 * 5)) do |token|
        t = ::AuthToken.new(
          user:,
          token:,
          purpose:
        )

        if request
          t.assign_attributes(
            api_ip_addr: request.ip,
            api_ip_ptr: get_ptr(request.ip),
            client_ip_addr: request.env['HTTP_CLIENT_IP'],
            client_ip_ptr: request.env['HTTP_CLIENT_IP'] && get_ptr(request.env['HTTP_CLIENT_IP']),
            user_agent: ::UserAgent.find_or_create!(request.user_agent || ''),
            client_version: request.user_agent || ''
          )
        end

        t.save!
        t
      end
    end
  end
end
