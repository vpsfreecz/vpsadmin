class WebauthnChallenge < ApplicationRecord
  belongs_to :user
  belongs_to :token, dependent: :delete
  belongs_to :user_agent
  belongs_to :password_recovery, optional: true

  enum :challenge_type, %i[registration authentication]

  def self.normalize_client_version(user_agent)
    value = user_agent.to_s.encode(
      Encoding::UTF_8, invalid: :replace, undef: :replace, replace: '?'
    )
    value.gsub(/[\u{10000}-\u{10FFFF}]/, '?')[0, columns_hash.fetch('client_version').limit]
  end

  def valid_to
    token.valid_to
  end

  def token_valid?
    valid_to > Time.now
  end
end
