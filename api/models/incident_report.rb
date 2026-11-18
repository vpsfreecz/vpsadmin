class IncidentReport < ApplicationRecord
  belongs_to :user
  belongs_to :vps
  belongs_to :ip_address_assignment
  belongs_to :filed_by, class_name: 'User'
  belongs_to :mailbox
  has_many :incident_policy_evaluations, dependent: :delete_all
  has_one :notice_action, class_name: 'VpsIncidentAction', foreign_key: :notice_incident_report_id

  scope :ordinary, -> { where('source_kind IS NULL OR source_kind <> ?', 'incident_policy_notice') }

  # Ownership restrictions remain with the resource; this scopes escalation history.
  def self.visible_in_owner_epoch(user)
    return all if user.role == :admin

    where(<<~SQL.squish, user.id)
      (NOT EXISTS (SELECT 1 FROM incident_policy_evaluations visible_e
        WHERE visible_e.incident_report_id = incident_reports.id)
        AND COALESCE(incident_reports.source_kind, '') <> 'incident_policy_notice') OR NOT EXISTS (
        SELECT 1 FROM vpses incident_vps WHERE incident_vps.id = incident_reports.vps_id
          AND incident_vps.user_id = ? AND incident_vps.incident_accounting_since IS NOT NULL
          AND (incident_reports.detected_at < incident_vps.incident_accounting_since OR
            (incident_reports.source_kind = 'incident_policy_notice' AND NOT EXISTS (
              SELECT 1 FROM vps_incident_actions notice_action
              WHERE notice_action.notice_incident_report_id = incident_reports.id
                AND notice_action.accounting_since = incident_vps.incident_accounting_since
            )))
      )
    SQL
  end

  def policy_notice?
    source_kind == 'incident_policy_notice'
  end

  def notice_kind
    return unless policy_notice? && notice_action

    notice_action.kind == 'warning' ? 'warning' : 'stop_completed'
  end

  def trigger_incident_report_id
    return unless policy_notice? && notice_action

    trigger = notice_action.incident_report
    trigger.id if trigger && trigger.user_id == user_id && trigger.vps_id == vps_id &&
                  (!notice_action.accounting_since || trigger.detected_at >= notice_action.accounting_since)
  end

  def notice_mail_state
    notice_action&.mail_state if policy_notice?
  end

  enum :vps_action, %i[none stop suspend disable_network], suffix: :action

  validates :subject, :text, presence: true, allow_blank: false

  before_create :set_reported_at
  around_create :evaluate_incident_policies
  after_rollback :reset_policy_evaluation_association, on: :create

  def notice_policy_key
    visible_notice_action&.policy_key
  end

  def notice_policy_label
    action = visible_notice_action
    return unless action

    action.saved_policy_evaluation&.dig('metadata', 'labels', I18n.locale.to_s) ||
      action.saved_policy_evaluation&.dig('metadata', 'labels', 'en')
  end

  def visible_notice_action
    return unless policy_notice? && notice_action

    action = notice_action
    trigger = action.incident_report
    action if action.user_id == user_id && action.vps_id == vps_id &&
              action.saved_policy_evaluation.is_a?(Hash) && action.saved_policy_evaluation.dig('metadata', 'key') == action.policy_key &&
              (!action.accounting_since || detected_at >= action.accounting_since) &&
              (!trigger || (trigger.user_id == user_id && trigger.vps_id == vps_id &&
                (!action.accounting_since || trigger.detected_at >= action.accounting_since)))
  end

  def ip_address
    ip_address_assignment && ip_address_assignment.ip_address
  end

  def raw_user_id
    user_id
  end

  def raw_vps_id
    vps_id
  end

  protected

  def reset_policy_evaluation_association
    # A retried creation can receive a different ID. Reset the cached query
    # constraint as well as loaded children, without querying the rolled-back ID.
    association(:incident_policy_evaluations).reset
    association(:incident_policy_evaluations).reset_scope
  end

  def evaluate_incident_policies(&block)
    if policy_notice?
      block.call
    else
      IncidentEscalation.create_report!(self, &block)
    end
  end

  def set_reported_at
    self.reported_at ||= Time.now
  end
end
