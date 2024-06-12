class UserDevice < ::ActiveRecord::Base
  LIFETIME = 30 * 24 * 60 * 60

  belongs_to :user
  belongs_to :token, dependent: :delete
  belongs_to :user_agent

  def usable?
    token && token.valid_to > Time.now
  end

  def touch
    token.update!(valid_to: Time.now + LIFETIME)
  end

  def close
    token.destroy!
    update!(token: nil)
  end
end
