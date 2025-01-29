class UserDevice < ApplicationRecord
  LIFETIME = 3 * 30 * 24 * 60 * 60

  NEXT_MULTI_FACTOR_AUTH = %w[require day week month].freeze

  belongs_to :user
  belongs_to :token, dependent: :delete
  belongs_to :user_agent

  scope :active, -> { where.not(token: nil) }

  validates :last_next_multi_factor_auth, inclusion: {
    in: NEXT_MULTI_FACTOR_AUTH
  }, unless: proc { |d| d.last_next_multi_factor_auth.blank? }
  validate :validate_skip_multi_factor_auth_until

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

  def skip_multi_factor_auth?
    skip_multi_factor_auth_until && skip_multi_factor_auth_until > Time.now
  end

  def validate_skip_multi_factor_auth_until
    return if skip_multi_factor_auth_until.nil?

    # rubocop:disable Style/GuardClause

    if skip_multi_factor_auth_until > (1.month.from_now + 60)
      errors.add(
        :skip_multi_factor_auth_until,
        'must not be more than a month from now'
      )
    end

    # rubocop:enable Style/GuardClause
  end
end
