require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::Authentication::WebauthnFactor < Operations::Base
    # The caller must lock the user and authority/challenge rows first. The
    # credential is then loaded and verified against its latest counter while
    # its row lock is held.
    def run(user, challenge, public_key_credential)
      credential = WebAuthn::Credential.from_get(
        stringify_credential_keys(public_key_credential)
      )
      stored = user.webauthn_credentials.where(
        external_id: Base64.strict_encode64(credential.raw_id),
        enabled: true
      ).lock.take!

      credential.verify(
        challenge.challenge,
        public_key: stored.public_key,
        sign_count: stored.sign_count
      )
      stored.update!(
        sign_count: credential.sign_count,
        last_use_at: Time.current,
        use_count: stored.use_count + 1
      )
      stored
    end

    protected

    def stringify_credential_keys(value)
      case value
      when Hash
        value.to_h do |key, item|
          [key.to_s, stringify_credential_keys(item)]
        end
      when Array
        value.map { |item| stringify_credential_keys(item) }
      else
        value
      end
    end
  end
end
