class Oauth2Client < ApplicationRecord
  has_many :oauth2_authorizations, dependent: :destroy

  validates :name, :client_id, :client_secret_hash, :redirect_uri,
            presence: true, allow_blank: false
  validates :client_id, uniqueness: true

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
end
