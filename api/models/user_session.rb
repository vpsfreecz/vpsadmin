class UserSession < ActiveRecord::Base
  belongs_to :user, class_name: 'User', foreign_key: :user_id
  belongs_to :admin, class_name: 'User', foreign_key: :admin_id
  belongs_to :user_agent
  belongs_to :session_token
  has_many :transaction_chains

  # @param user [::User]
  # @param token [::SessionToken]
  # @return [::UserSession]
  def self.find_for!(user, token)
    find_by!(
      user: user,
      session_token: token,
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
