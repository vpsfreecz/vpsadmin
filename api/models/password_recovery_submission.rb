require 'digest'

class PasswordRecoverySubmission < ApplicationRecord
  CLAIM_TIMEOUT = 5.minutes
  MAX_ATTEMPTS = 3
  MAX_PENDING = 100
  IDENTIFIER_INTERVAL = 10.minutes
  MAX_PER_SOURCE = 10
  SOURCE_INTERVAL = 10.minutes
  RECORD_RETENTION = 1.day
  USER_AGENT_LIMIT = 512

  EnqueueResult = Data.define(:status, :submission, :retry_after) do
    def accepted?
      status == :accepted
    end

    def rate_limited?
      status == :rate_limited
    end

    def busy?
      status == :busy
    end
  end

  belongs_to :oauth2_client, optional: true

  validates :identifier, :locale, presence: true, allow_blank: false, on: :create
  validates :identifier_digest, presence: true, allow_blank: false

  scope :pending, -> { where(finished_at: nil) }
  scope :claimable, lambda {
    pending
      .where('processing_started_at IS NULL OR processing_started_at < ?', CLAIM_TIMEOUT.ago)
      .where('attempts < ?', MAX_ATTEMPTS)
  }

  def self.enqueue!(identifier:, locale:, oauth2_client:, request:)
    normalized_identifier = identifier.to_s.strip[0, 127]
    return EnqueueResult.new(:accepted, nil, nil) if normalized_identifier.blank?

    identifier_digest = digest_identifier(normalized_identifier)
    source = client_ip(request).to_s[0, 46]

    with_queue_lock do |config|
      next EnqueueResult.new(:unavailable, nil, nil) unless config&.value

      now = Time.current
      retry_at = [
        identifier_retry_at(identifier_digest, now),
        source_retry_at(source, now)
      ].compact.max
      if retry_at
        retry_after = [(retry_at - Time.current).ceil, 1].max
        ::PasswordEventCounter.record_recovery_submission!(:rate_limited, at: now)
        next EnqueueResult.new(:rate_limited, nil, retry_after)
      end

      pending_count = pending.count
      if pending_count >= MAX_PENDING
        ::PasswordEventCounter.record_recovery_submission!(:queue_full, at: now)
        next EnqueueResult.new(:busy, nil, nil)
      end

      submission = create!(
        identifier: normalized_identifier,
        identifier_digest:,
        locale: locale.to_s[0, 16],
        oauth2_client:,
        client_ip_addr: source,
        user_agent: request.user_agent.to_s[0, USER_AGENT_LIMIT]
      )
      ::PasswordEventCounter.record_recovery_submission!(:accepted, at: now)
      if pending_count + 1 == MAX_PENDING
        ::PasswordEventCounter.record_recovery_queue_capacity_reached!(at: now)
      end
      EnqueueResult.new(:accepted, submission, nil)
    end
  end

  def self.claim_next
    with_queue_lock do
      finish_stale_exhausted!(Time.current)
      submission = claimable.order(:id).lock('FOR UPDATE SKIP LOCKED').first
      return unless submission

      submission.update!(
        processing_started_at: Time.current,
        attempts: submission.attempts + 1
      )
      submission
    end
  end

  def retry_or_finish!
    self.class.with_queue_lock do
      lock!
      finish_record! if attempts >= MAX_ATTEMPTS
    end
  end

  def finish!
    self.class.with_queue_lock do
      lock!
      finish_record!
    end
  end

  def self.with_queue_lock
    transaction do
      config = ::SysConfig.where(
        category: 'core',
        name: 'password_recovery_enabled'
      ).lock.take
      yield config
    end
  end

  def self.client_ip(request)
    request.env['HTTP_X_REAL_IP'].presence || request.ip
  end

  def self.digest_identifier(identifier)
    Digest::SHA256.hexdigest(identifier.downcase)
  end

  def self.identifier_retry_at(identifier_digest, now)
    created_at = where(identifier_digest:)
                 .where('created_at > ?', now - IDENTIFIER_INTERVAL)
                 .order(created_at: :desc)
                 .pick(:created_at)
    created_at && (created_at + IDENTIFIER_INTERVAL)
  end

  def self.source_retry_at(source, now)
    recent = where(client_ip_addr: source)
             .where('created_at > ?', now - SOURCE_INTERVAL)
             .order(created_at: :desc)
             .limit(MAX_PER_SOURCE)
             .pluck(:created_at)
    return unless recent.length >= MAX_PER_SOURCE

    recent.last + SOURCE_INTERVAL
  end

  def self.finish_stale_exhausted!(now)
    pending
      .where('attempts >= ?', MAX_ATTEMPTS)
      .where(
        'processing_started_at IS NULL OR processing_started_at < ?',
        now - CLAIM_TIMEOUT
      )
      .update_all(
        identifier: nil,
        user_agent: nil,
        processing_started_at: nil,
        finished_at: now,
        updated_at: now
      )
  end

  private_class_method :client_ip, :digest_identifier,
                       :identifier_retry_at, :source_retry_at,
                       :finish_stale_exhausted!

  protected

  def finish_record!
    return if finished_at?

    update!(
      identifier: nil,
      user_agent: nil,
      processing_started_at: nil,
      finished_at: Time.current
    )
  end
end
