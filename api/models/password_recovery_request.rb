class PasswordRecoveryRequest < ApplicationRecord
  # Request provenance is retained only with this 30-day recovery record.
  # Referencing UserAgent would retain attacker-controlled public input in its
  # permanent dictionary after the recovery request is deleted.
  belongs_to :oauth2_client, optional: true
  belongs_to :password_recovery_submission, optional: true
  belongs_to :mail_log, optional: true
  has_many :password_recoveries, dependent: :destroy

  validates :recipient_email, :locale, presence: true, allow_blank: false
end
