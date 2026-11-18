class VpsIncidentPolicy < ApplicationRecord
  belongs_to :vps
  has_paper_trail

  validates :policy_key, inclusion: { in: ->(_record) { IncidentEscalation::RULES.keys } }
  validates :warning_limit_override, :stop_limit_override,
            numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 2_147_483_647 }, allow_nil: true
  validate :validate_limits

  def validate_limits
    config = IncidentEscalation.config(policy_key:, lock: true)
    warning = warning_limit_override || config[:warning] || IncidentEscalation.rule(policy_key).warning_limit
    stop = stop_limit_override || config[:stop] || IncidentEscalation.rule(policy_key).stop_limit
    return unless warning.is_a?(Integer) && stop.is_a?(Integer)

    errors.add(:stop_limit_override, 'must be at least the effective warning limit') if stop < warning
  rescue IncidentEscalation::InvalidConfiguration => e
    errors.add(:base, e.message)
  end
end
