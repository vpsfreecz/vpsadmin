require 'digest'

module VpsAdmin
  module API
    class CryptoProvider
      def self.encrypt(*tokens)
        Digest::MD5.hexdigest(tokens.join(''))
      end

      def self.matches?(crypted, *tokens)
        crypted == encrypt(*tokens)
      end
    end
  end
end
