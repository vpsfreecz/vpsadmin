require 'uri'

class Oauth2Client < ApplicationRecord
  has_many :oauth2_authorizations, dependent: :destroy
  has_many :password_recovery_submissions, dependent: :nullify
  has_many :password_recovery_requests, dependent: :nullify

  validates :name, :client_id, :client_secret_hash, :redirect_uri,
            presence: true, allow_blank: false
  validates :client_id, uniqueness: true
  validate :authorization_start_uri_is_safe

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

  protected

  def authorization_start_uri_is_safe
    return if authorization_start_uri.blank?

    uri = URI.parse(authorization_start_uri)
    valid = %w[http https].include?(uri.scheme) && uri.host.present? &&
            uri.userinfo.nil? && uri.fragment.nil?
    errors.add(:authorization_start_uri, 'must be an absolute HTTP(S) URI without user info or a fragment') unless valid
  rescue URI::InvalidURIError
    errors.add(:authorization_start_uri, 'must be an absolute HTTP(S) URI without user info or a fragment')
  end
end
