class UserAgent < ActiveRecord::Base
  has_many :user_sessions

  def self.find_or_create!(user_agent)
    hash = Digest::SHA1.hexdigest(user_agent)
    find_by(agent_hash: hash) || create!(
      agent: user_agent,
      agent_hash: hash
    )
  end
end
