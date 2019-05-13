require 'json'

class AuthToken < ActiveRecord::Base
  belongs_to :user
  belongs_to :user_agent
  belongs_to :token, dependent: :delete

  serialize :opts, JSON
  validates :user_id, presence: true

  def valid_to
    token.valid_to
  end

  def token_valid?
    valid_to > Time.now
  end

  def to_s
    token.to_s
  end
end
