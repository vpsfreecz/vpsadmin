require 'digest'
require 'securerandom'

class PasswordRecovery < ApplicationRecord
  EMAIL_LIFETIME = 1.hour
  SESSION_LIFETIME = 15.minutes
  COMPLETION_LIFETIME = 15.minutes
  MAX_TOTP_FAILED_ATTEMPTS = 5
  RECORD_RETENTION = 30.days

  belongs_to :password_recovery_request
  belongs_to :user
  has_many :webauthn_challenges, dependent: :destroy

  enum :outcome, %i[recoverable no_mfa unavailable]

  validates :email_snapshot, presence: true, allow_blank: false
  validates :email_token_digest, presence: true, if: :email_token_required?
  validates :email_expires_at, presence: true, if: :recoverable?
  validates :session_token_digest, :session_expires_at,
            presence: true,
            if: :email_consumed_at?

  scope :active, lambda {
    where(completed_at: nil, invalidated_at: nil)
  }

  def self.digest_token(token)
    Digest::SHA256.hexdigest(token)
  end

  def self.generate_token
    SecureRandom.urlsafe_base64(32, false)
  end

  def self.find_by_email_token(token)
    active.find_by(email_token_digest: digest_token(token))
  end

  def self.find_any_by_email_token(token)
    find_by(email_token_digest: digest_token(token))
  end

  def self.find_by_session_token(token)
    active.find_by(session_token_digest: digest_token(token))
  end

  def self.find_any_by_session_token(token)
    find_by(session_token_digest: digest_token(token))
  end

  def self.find_recently_completed_by_session_token(token)
    where(session_token_digest: digest_token(token))
      .where(completed_at: COMPLETION_LIFETIME.ago..Time.current)
      .take
  end

  def email_token_usable?
    active_state? && recoverable? && email_consumed_at.nil? && email_expires_at&.future?
  end

  def session_usable?
    active_state? && recoverable? && email_consumed_at? && session_expires_at&.future?
  end

  def active_state?
    completed_at.nil? && invalidated_at.nil?
  end

  def mfa_verified?
    mfa_verified_at.present? &&
      [verified_totp_device_id, verified_webauthn_credential_id].compact.one?
  end

  def verify_mfa_with!(factor)
    unless factor.user_id == user_id
      raise ArgumentError, 'MFA factor belongs to another user'
    end

    case factor
    when UserTotpDevice
      update!(
        mfa_verified_at: Time.current,
        verified_totp_device_id: factor.id,
        verified_webauthn_credential_id: nil
      )
    when WebauthnCredential
      update!(
        mfa_verified_at: Time.current,
        verified_totp_device_id: nil,
        verified_webauthn_credential_id: factor.id
      )
    else
      raise ArgumentError, "unsupported MFA factor: #{factor.class}"
    end
  end

  def self.active_verified_with(factor)
    active.where(verified_factor_column(factor) => factor.id)
  end

  def self.lock_for_totp_verification(user, current: nil)
    relation = active.where(user:).where.not(verified_totp_device_id: nil)
    relation = relation.or(where(user:, id: current.id)) if current
    locked = relation.order(:id).lock.to_a

    [
      current && locked.find { |recovery| recovery.id == current.id },
      locked.select do |recovery|
        recovery.active_state? && recovery.verified_totp_device_id.present?
      end
    ]
  end

  def self.invalidate_locked_verified_with!(recoveries, factor, except: nil)
    column = verified_factor_column(factor)
    except_id = except&.id
    now = Time.current
    recoveries.each do |recovery|
      next if recovery.id == except_id || recovery.public_send(column) != factor.id

      recovery.update!(invalidated_at: now)
    end
  end

  def self.verified_factor_column(factor)
    case factor
    when UserTotpDevice
      :verified_totp_device_id
    when WebauthnCredential
      :verified_webauthn_credential_id
    else
      raise ArgumentError, "unsupported MFA factor: #{factor.class}"
    end
  end

  private_class_method :verified_factor_column

  def consume_email_token!
    unless email_token_usable?
      errors.add(:email_token_digest, 'is no longer usable')
      raise ActiveRecord::RecordInvalid, self
    end

    token = self.class.generate_token
    update!(
      email_consumed_at: Time.current,
      email_token_digest: nil,
      session_token_digest: self.class.digest_token(token),
      session_expires_at: Time.current + SESSION_LIFETIME
    )
    token
  end

  def invalidate!
    update!(invalidated_at: Time.current) unless invalidated_at?
  end

  protected

  def email_token_required?
    recoverable? && email_consumed_at.nil?
  end
end
