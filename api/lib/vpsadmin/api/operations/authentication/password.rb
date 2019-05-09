require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::Password < Operations::Base
    Result = Struct.new(:user, :authenticated, :complete, :token) do
      alias_method :authenticated?, :authenticated
      alias_method :complete?, :complete
    end

    # @param username [String]
    # @param password [String]
    # @param multi_factor [Boolean]
    # @return [Result, nil]
    def run(username, password, multi_factor: true)
      user = ::User.unscoped.where(
        object_state: [
          ::User.object_states[:active],
          ::User.object_states[:suspended],
        ],
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
      end

      ret = Result.new(user, authenticated, !user.totp_enabled)

      if multi_factor && user.totp_enabled
        ret.token = ::Token.for_new_record!(Time.now + 60*5) do |token|
          ::AuthToken.create!(
            user: user,
            token: token,
          )
        end
      end

      ret
    end
  end
end
