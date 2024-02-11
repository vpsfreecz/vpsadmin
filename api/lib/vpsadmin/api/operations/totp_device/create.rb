require 'rotp'
require 'vpsadmin/api/operations/base'

module VpsAdmin::API
  class Operations::TotpDevice::Create < Operations::Base
    # @param user [::User]
    # @param label [String]
    # @return [::UserTotpDevice]
    def run(user, label)
      5.times do
        return ::UserTotpDevice.create!(
          user:,
          label:,
          secret: ROTP::Base32.random
        )
      rescue ActiveRecord::RecordNotUnique
        next
      end

      raise Exceptions::OperationError, 'unable to generate totp secret'
    end
  end
end
