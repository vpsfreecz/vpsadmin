class VpsEvidenceInterval < ApplicationRecord
  attr_readonly :vps_id, :signal, :user_id, :accounting_since, :incident_report_id, :from_at, :to_at, :credit_us, :accepted_at, :measurement, :peak_unit, :peak_value, :peak_is_lower_bound, :evidence
  attribute :evidence, :json
  belongs_to :vps
  belongs_to :user
  belongs_to :incident_report, optional: true

  validate do
    errors.add(:accepted_at, 'must identify a live acceptance only') if incident_report_id.nil? == accepted_at.nil?
  end

  validate do
    values = [measurement, peak_unit, peak_value, peak_is_lower_bound]
    unless values.all?(&:nil?) || (values.none?(&:nil?) && measurement.is_a?(String) && measurement.bytesize.between?(1, 64) &&
           peak_unit.is_a?(String) && peak_unit.bytesize.between?(1, 32) && peak_value.is_a?(Integer) && peak_value >= 0 &&
           [true, false].include?(peak_is_lower_bound))
      errors.add(:peak_value, 'Invalid typed measurement')
    end
  end

  scope :live, -> { where(incident_report_id: nil) }

  def self.in_window(vps, signal, config, now:)
    live.where(vps_id: vps.id, signal:, user_id: vps.user_id, accounting_since: vps.incident_accounting_since)
        .where('to_at > ? AND from_at < ?', now - config.fetch(:window_seconds), now)
        .order(:from_at, :id)
  end

  # Open lower window bound, closed upper bound; all persisted durations are
  # integer microseconds. Clip expiration without rounding accepted time up.
  def clipped(from:, to:)
    first = [from_at, from].max
    last = [to_at, to].min
    return if first >= last

    { from_at: first, to_at: last, credit_us: ((last.to_r - first.to_r) * 1_000_000).to_i,
      measurement:, peak_unit:, peak_value:, peak_is_lower_bound:, evidence: }
  end
end
