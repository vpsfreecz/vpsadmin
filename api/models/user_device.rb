class UserDevice < ::ActiveRecord::Base
  LIFETIME = 30 * 24 * 60 * 60

  belongs_to :user
  belongs_to :token, dependent: :delete
  belongs_to :user_agent

  scope :active, -> { where.not(token: nil) }

  def user_agent_string
    user_agent.agent
  end

  def usable?
    token && token.valid_to > Time.now
  end

  def refresh
    token.regenerate!
  end

  def touch
    now = Time.now
    token.update!(valid_to: now + LIFETIME)
    update!(last_seen_at: now)
  end

  def close
    token.destroy!
    update!(token: nil)
  end
end
