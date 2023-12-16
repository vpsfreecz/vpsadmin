class Oauth2Authorization < ::ActiveRecord::Base
  belongs_to :oauth2_client
  belongs_to :user
  belongs_to :code, class_name: 'Token', dependent: :destroy
  belongs_to :user_session
  belongs_to :refresh_token, class_name: 'Token', dependent: :destroy
  belongs_to :single_sign_on
  serialize :scope, JSON

  def check_code_validity(redirect_uri)
    code.valid_to > Time.now && oauth2_client.redirect_uri == redirect_uri
  end

  def refreshable?
    refresh_token && refresh_token.valid_to > Time.now
  end

  def active?
    (code && code.valid_to > Time.now) || (user_session && user_session.closed_at.nil?)
  end

  def close
    valid_to = nil

    if refresh_token
      valid_to = refresh_token.valid_to
      refresh_token.destroy!
      update!(refresh_token: nil)
    end

    if user_session && !user_session.closed_at
      if user_session.session_token
        fail "expected user_session.session_token to be nil on user_session=#{user_session.id}"
      end

      user_session.update!(closed_at: valid_to || Time.now)
    end
  end
end
