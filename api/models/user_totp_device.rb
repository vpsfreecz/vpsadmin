require 'rotp'

class UserTotpDevice < ActiveRecord::Base
  belongs_to :user

  validates :label, presence: true

  # @return [String]
  def provisioning_uri
    totp.provisioning_uri(user.login)
  end

  # @return [ROTP::TOTP]
  def totp
    @totp ||= ROTP::TOTP.new(secret, issuer: SysConfig.get(:core, 'totp_issuer'))
  end
end
