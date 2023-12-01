class Oauth2Authorization < ::ActiveRecord::Base
  belongs_to :oauth2_client
  belongs_to :user
  belongs_to :code, class_name: 'Token', dependent: :destroy
  belongs_to :user_session
  belongs_to :refresh_token, class_name: 'Token', dependent: :destroy
  serialize :scope, JSON

  def check_code_validity(redirect_uri)
    code.valid_to > Time.now && oauth2_client.redirect_uri == redirect_uri
  end
end
