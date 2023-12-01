class Oauth2Client < ::ActiveRecord::Base
  has_many :oauth2_authorizations, dependent: :destroy

  def check_secret(client_secret)
    begin
      ::BCrypt::Password.new(client_secret_hash) == client_secret
    rescue BCrypt::Errors::InvalidHash
      false
    end
  end
end
