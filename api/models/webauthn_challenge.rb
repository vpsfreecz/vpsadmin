class WebauthnChallenge < ApplicationRecord
  belongs_to :user
  belongs_to :token, dependent: :delete
  belongs_to :user_agent

  enum :challenge_type, %i[registration authentication]

  def valid_to
    token.valid_to
  end

  def token_valid?
    valid_to > Time.now
  end
end
