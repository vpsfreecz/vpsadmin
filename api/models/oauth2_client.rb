require 'uri'

class Oauth2Client < ApplicationRecord
  BOOLEAN_TYPE = ActiveModel::Type::Boolean.new.freeze

  has_many :oauth2_authorizations, dependent: :destroy
  has_many :password_recovery_submissions, dependent: :nullify
  has_many :password_recovery_requests, dependent: :nullify

  validates :name, :client_id, :client_secret_hash, :redirect_uri,
            presence: true, allow_blank: false
  validates :client_id, uniqueness: true
  validate :authorization_start_uri_is_safe
  validate :default_client_has_authorization_start_uri

  # Must correspond to {UserSession.token_lifetime}, except for permanent
  enum :access_token_lifetime, %i[fixed renewable_manual renewable_auto]

  def check_secret(client_secret)
    ::BCrypt::Password.new(client_secret_hash) == client_secret
  rescue BCrypt::Errors::InvalidHash
    false
  end

  def set_secret(client_secret)
    self.client_secret_hash = ::BCrypt::Password.create(client_secret).to_s
  end

  def self.default_client
    find_by(is_default: true)
  end

  def is_default
    self[:is_default] == true
  end

  def is_default=(value)
    self[:is_default] = BOOLEAN_TYPE.cast(value) ? true : nil
  end

  def save_with_default!
    self.class.transaction do
      if is_default?
        self.class.order(:id).lock.load
        clear_previous_default!
      end

      save!
    end
  end

  def update_with_default!(attributes, client_secret: nil)
    self.class.transaction do
      self.class.order(:id).lock.load
      reload
      assign_attributes(attributes)
      set_secret(client_secret) if client_secret
      clear_previous_default! if is_default?
      save!
    end
  end

  def destroy_with_password_recoveries!
    ::PasswordRecoverySubmission.with_queue_lock do
      submissions = ::PasswordRecoverySubmission.pending
                                                .where(oauth2_client_id: id)
                                                .order(:id)
                                                .lock
                                                .to_a
      lock!
      recoveries = ::PasswordRecovery.joins(:password_recovery_request)
                                     .active
                                     .where(
                                       password_recovery_requests: {
                                         oauth2_client_id: id
                                       }
                                     )
                                     .order('password_recoveries.id')
                                     .lock
                                     .to_a
      now = Time.current
      submissions.each(&:finish_locked!)
      recoveries.each { |recovery| recovery.update!(invalidated_at: now) }
      destroy!
    end
  end

  protected

  def clear_previous_default!
    previous = self.class.where(is_default: true)
    previous = previous.where.not(id:) if persisted?
    previous.update_all(is_default: nil, updated_at: Time.current)
  end

  def authorization_start_uri_is_safe
    return if authorization_start_uri.blank?

    uri = URI.parse(authorization_start_uri)
    valid = %w[http https].include?(uri.scheme) && uri.host.present? &&
            uri.userinfo.nil? && uri.fragment.nil?
    errors.add(:authorization_start_uri, 'must be an absolute HTTP(S) URI without user info or a fragment') unless valid
  rescue URI::InvalidURIError
    errors.add(:authorization_start_uri, 'must be an absolute HTTP(S) URI without user info or a fragment')
  end

  def default_client_has_authorization_start_uri
    return unless is_default? && authorization_start_uri.blank?

    errors.add(:authorization_start_uri, 'must be set on the default OAuth2 client')
  end
end
