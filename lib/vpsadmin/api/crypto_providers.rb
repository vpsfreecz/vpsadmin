require 'digest'
require 'bcrypt'

module VpsAdmin
  module API
    module CryptoProviders
      PROVIDERS = %i(md5 bcrypt)

      def self.provider(name)
        const_get(name.to_s.classify)
      end

      def self.update?(name)
        PROVIDERS.last != name.to_sym
      end

      def self.current
        last = PROVIDERS.last

        if block_given?
          yield(last, provider(last))
        else
          provider(last)
        end
      end

      class Md5
        def self.encrypt(*tokens)
          Digest::MD5.hexdigest(tokens.join(''))
        end

        def self.matches?(crypted, *tokens)
          crypted == encrypt(*tokens)
        end
      end

      class Bcrypt
        def self.encrypt(_, password)
          ::BCrypt::Password.create(password).to_s
        end

        def self.matches?(crypted, _, password)
          begin
            ::BCrypt::Password.new(crypted) == password
            
          rescue BCrypt::Errors::InvalidHash
            false
          end
        end
      end
    end
  end
end
