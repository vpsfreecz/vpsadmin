class VpsIncidentPolicy < ApplicationRecord
  belongs_to :vps
  has_paper_trail

  validates :incident_type, inclusion: { in: ->(_record) { IncidentEscalation::RULES.keys } }
  validates :warning_limit_override, :stop_limit_override,
            numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :validate_limits

  def validate_limits
    config = IncidentEscalation.config(incident_type:)
    warning = warning_limit_override || config[:warning]
    stop = stop_limit_override || config[:stop]
    return unless warning.is_a?(Integer) && stop.is_a?(Integer)

    errors.add(:stop_limit_override, 'must be at least the effective warning limit') if stop < warning
  rescue IncidentEscalation::InvalidConfiguration => e
    errors.add(:base, e.message)
  end
end
