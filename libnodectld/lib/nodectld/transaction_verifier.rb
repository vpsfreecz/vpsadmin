require 'base64'
require 'openssl'
require 'singleton'

module NodeCtld
  class TransactionVerifier
    include Singleton

    class << self
      %i(verify_base64).each do |m|
        define_method(m) do |*args, &block|
          instance.send(m, *args, &block)
        end
      end
    end

    def initialize
      path = $CFG.get(:vpsadmin, :transaction_public_key)
      @key = OpenSSL::PKey::RSA.new(File.read(path))
    rescue Errno::ENOENT
      fail "Transaction public key file not found at '#{path}'"
    end

    def verify_base64(data, signature)
      digest = OpenSSL::Digest::SHA256.new
      key.verify(digest, Base64.decode64(signature), data)
    end

    protected
    attr_reader :key
  end
end
