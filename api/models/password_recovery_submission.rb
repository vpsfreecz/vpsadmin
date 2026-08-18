class PasswordRecoverySubmission < ApplicationRecord
  CLAIM_TIMEOUT = 5.minutes
  MAX_ATTEMPTS = 3
  MAX_PENDING = 1_000
  MAX_PER_SOURCE = 10
  SOURCE_INTERVAL = 10.minutes
  RECORD_RETENTION = 1.day
  USER_AGENT_LIMIT = 512

  belongs_to :oauth2_client, optional: true

  validates :identifier, :locale, presence: true, allow_blank: false

  scope :claimable, lambda {
    where('processing_started_at IS NULL OR processing_started_at < ?', CLAIM_TIMEOUT.ago)
      .where('attempts < ?', MAX_ATTEMPTS)
  }

  def self.enqueue!(identifier:, locale:, oauth2_client:, request:)
    normalized_identifier = identifier.to_s.strip[0, 127]
    return if normalized_identifier.blank?

    source = client_ip(request).to_s[0, 46]

    transaction do
      limit = ::SysConfig.where(
        category: 'core',
        name: 'password_recovery_enabled'
      ).lock.take
      next unless limit
      next if count >= MAX_PENDING
      next if where(client_ip_addr: source)
              .where('created_at > ?', SOURCE_INTERVAL.ago)
              .count >= MAX_PER_SOURCE

      create!(
        identifier: normalized_identifier,
        locale: locale.to_s[0, 16],
        oauth2_client:,
        client_ip_addr: source,
        user_agent: request.user_agent.to_s[0, USER_AGENT_LIMIT]
      )
    end
  end

  def self.claim_next
    transaction do
      submission = claimable.order(:id).lock('FOR UPDATE SKIP LOCKED').first
      return unless submission

      submission.update!(
        processing_started_at: Time.current,
        attempts: submission.attempts + 1
      )
      submission
    end
  end

  def retry_or_discard!
    with_lock do
      destroy! if attempts >= MAX_ATTEMPTS
    end
  end

  def self.client_ip(request)
    request.env['HTTP_X_REAL_IP'].presence || request.ip
  end
  private_class_method :client_ip
end
