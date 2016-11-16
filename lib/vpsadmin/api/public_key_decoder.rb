require 'base64'

module VpsAdmin::API
  # This class can parse public keys from the format used by SSH
  class PublicKeyDecoder
    attr_reader :comment

    def initialize(str)
      parts = str.split

      @comment = parts[2]
      @encoded_key = Base64.decode64(parts[1])
    end

    # MD5 fingerprint as defined in RFC 4716
    def fingerprint
      OpenSSL::Digest::MD5.hexdigest(@encoded_key).scan(/../).join(':')
    end
  end
end
