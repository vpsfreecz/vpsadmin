class UserSession < ActiveRecord::Base
  belongs_to :user, class_name: 'User', foreign_key: :user_id
  belongs_to :admin, class_name: 'User', foreign_key: :admin_id
  belongs_to :user_agent
  belongs_to :session_token
  has_many :oauth2_authorizations
  has_many :transaction_chains

  serialize :scope, JSON

  # @param user [::User]
  # @param token [::SessionToken]
  # @param auth_type [Symbol]
  # @return [::UserSession]
  def self.find_for!(user, token, auth_type)
    find_by!(
      user: user,
      session_token: token,
      auth_type: auth_type,
      closed_at: nil,
    )
  end

  def self.current
    Thread.current[:user_session]
  end

  def self.current=(s)
    Thread.current[:user_session] = s
  end

  def close!
    token = session_token

    update!(
      session_token: nil,
      closed_at: Time.now,
    )

    token && token.destroy!
  end

  def user_agent_string
    user_agent.agent
  end
end
