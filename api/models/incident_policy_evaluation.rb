# Creation-time membership and decisions are immutable; physical/mail state is
# kept separately on VpsIncidentAction.
class IncidentPolicyEvaluation < ApplicationRecord
  attribute :snapshot, :json
  belongs_to :incident_report
  has_one :vps_incident_action
  attr_readonly :incident_report_id, :policy_key, :matched, :state, :evaluated_at, :snapshot

  scope :matched, -> { where(matched: true) }
  scope :member_visible, -> { matched.where(state: %w[recorded audit_only]) }

  def label(language = :en)
    labels = snapshot.fetch('metadata').fetch('labels')
    labels[language.to_s] || labels.fetch('en')
  end

  # Bounded, saved facts for the ordinary source-mail producer. No current
  # configuration access or selector execution belongs to this projection.
  def mail_summary(language: :en)
    return unless matched && %w[recorded audit_only].include?(state) && snapshot.is_a?(Hash)

    context = snapshot.fetch('context')
    effective = snapshot.fetch('effective')
    return unless context.is_a?(Hash) && effective.is_a?(Hash)
    return unless %w[count_7d count_30d].all? { |key| context[key].is_a?(Integer) && context[key] >= 0 } &&
                  %w[warning_limit stop_limit].all? { |key| effective[key].is_a?(Integer) && effective[key] > 0 } &&
                  effective['stop_limit'] >= effective['warning_limit'] && IncidentEscalation::MODES.include?(effective['mode']) &&
                  %w[stop_exempt suppress_actions].all? { |key| [true, false].include?(effective[key]) }

    {
      key: policy_key, label: label(language), evaluated_at:,
      count_7d: context.fetch('count_7d'), count_30d: context.fetch('count_30d'),
      warning_limit: effective.fetch('warning_limit'), stop_limit: effective.fetch('stop_limit'),
      mode: effective.fetch('mode'), stop_exempt: effective.fetch('stop_exempt'),
      suppress_actions: effective.fetch('suppress_actions'),
      warning_period_days: 7, stop_period_days: 30, repeat_stop_hours: 24,
      stop_enforced: effective.fetch('mode') == 'enforce' && !effective.fetch('stop_exempt') && !effective.fetch('suppress_actions')
    }
  rescue KeyError, TypeError, ArgumentError
    nil
  end
end
