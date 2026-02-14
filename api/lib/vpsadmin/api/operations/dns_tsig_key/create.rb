require 'vpsadmin/api/operations/base'
require 'securerandom'

module VpsAdmin::API
  class Operations::DnsTsigKey::Create < Operations::Base
    # @param attrs [Hash]
    # @return [::DnsTsigKey]
    def run(attrs)
      tsig_key = ::DnsTsigKey.new(attrs)

      if ::User.current.role == :admin
        if tsig_key.user.nil?
          tsig_key.errors.add(:user, 'must exist')
          raise ActiveRecord::RecordInvalid, tsig_key
        end

        tsig_key.name = "#{tsig_key.user_id}-#{tsig_key.name}" if tsig_key.user
      else
        tsig_key.user = ::User.current
        tsig_key.name = "#{::User.current.id}-#{tsig_key.name}"
      end

      tsig_key.secret = generate_key(tsig_key.algorithm)
      tsig_key.save!
      tsig_key
    end

    protected

    def generate_key(algorithm)
      length = {
        'hmac-sha224' => 28,
        'hmac-sha256' => 32,
        'hmac-sha384' => 48,
        'hmac-sha512' => 64
      }[algorithm]

      raise "Unsupported algorithm #{algorithm}" if length.nil?

      SecureRandom.base64(length)
    end
  end
end
