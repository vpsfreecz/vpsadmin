require 'base64'
require 'openssl'
require 'singleton'

module VpsAdmin::API
  class TransactionSigner
    class Error < ::StandardError ; end

    include Singleton

    class << self
      %i(can_sign? unlock sign_base64).each do |m|
        define_method(m) do |*args, &block|
          instance.send(m, *args, &block)
        end
      end
    end

    def initialize
      @key = nil
    end

    def can_sign?
      !key.nil?
      # TODO: return true only if key is set
      true
    end

    # @param passphrase [String]
    # @return [Boolean]
    def unlock(passphrase)
      raise Error, 'already unlocked' if @key

      @key = OpenSSL::PKey::RSA.new(get_key, passphrase)
      true

    rescue OpenSSL::PKey::RSAError
      raise Error, 'invalid passphrase'
    end

    # @param data [String]
    # @return [String] base64 encoded signature
    def sign_base64(data)
      # TODO: always sign data
      if key
        digest = OpenSSL::Digest::SHA256.new
        signature = key.sign(digest, data)
        Base64.encode64(signature)
      else
        nil
      end
    end

    protected
    attr_reader :key

    def get_key
      ::SysConfig.get(:core, :transaction_key)
    end
  end
end
