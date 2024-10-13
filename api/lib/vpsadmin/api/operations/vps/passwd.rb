require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Vps::Passwd < Operations::Base
    # @param vps [::Vps]
    # @param password_type [String]
    # @return [Array(::TransactionChain, String)]
    def run(vps, password_type)
      password = generate_password(password_type)

      [TransactionChains::Vps::Passwd.fire(vps, password).first, password]
    end

    protected

    def generate_password(password_type)
      case password_type
      when 'secure'
        chars = ('a'..'z').to_a + ('A'..'Z').to_a + (0..9).to_a
        (0..19).map { chars.sample }.join
      when 'simple'
        chars = ('a'..'z').to_a + (2..9).to_a
        (0..7).map { chars.sample }.join
      else
        raise "unknown password type #{password_type.inspect}"
      end
    end
  end
end
