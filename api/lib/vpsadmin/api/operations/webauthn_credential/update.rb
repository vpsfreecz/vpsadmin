require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::WebauthnCredential::Update < Operations::Base
    def run(credential, attrs)
      Operations::Authentication::MfaFactorChange.run(
        credential,
        revoke_recovery: attrs[:enabled] == false
      ) do |locked_credential, _user|
        locked_credential.update!(attrs)
        locked_credential
      end
    end
  end
end
