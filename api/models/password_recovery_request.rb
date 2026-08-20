class PasswordRecoveryRequest < ApplicationRecord
  belongs_to :oauth2_client, optional: true
  belongs_to :password_recovery_submission, optional: true
  belongs_to :mail_log, optional: true
  has_many :password_recoveries, dependent: :destroy

  validates :recipient_email, :locale, presence: true, allow_blank: false
end
