class UserSession < ActiveRecord::Base
  belongs_to :user, class_name: 'User', foreign_key: :user_id
  belongs_to :admin, class_name: 'User', foreign_key: :admin_id
  belongs_to :user_agent
  belongs_to :token
  has_many :oauth2_authorizations
  has_many :transaction_chains

  serialize :scope, coder: JSON
  enum token_lifetime: %i(fixed renewable_manual renewable_auto permanent)

  def self.current
    Thread.current[:user_session]
  end

  def self.current=(s)
    Thread.current[:user_session] = s
  end

  # @param token_lifetime [String]
  # @param token_interval [Integer, nil]
  def refresh_token!(token_lifetime, token_interval)
    old_token = self.token

    valid_to = token_lifetime == 'permanent' ? nil : Time.now + token_interval
    new_token = ::Token.get!(owner: self, valid_to:)

    update!(token: new_token)
    old_token && old_token.destroy!
  end

  def renew_token!
    token.update!(valid_to: Time.now + token_interval)
  end

  def close!
    old_token = self.token

    update!(
      token: nil,
      closed_at: Time.now
    )

    old_token && old_token.destroy!
  end

  def token_fragment
    token_str && token_str[0..9]
  end

  def token_full
    token_str
  end

  def scope_str
    scope.join(' ')
  end

  def user_agent_string
    user_agent.agent
  end
end
