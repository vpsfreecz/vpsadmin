require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::WebauthnCredential::Delete < Operations::Base
    def run(credential)
      Operations::Authentication::MfaFactorChange.run(
        credential,
        revoke_recovery: true
      ) do |locked_credential, _user|
        locked_credential.destroy!
      end
    end
  end
end
