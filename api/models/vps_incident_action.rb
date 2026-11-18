class VpsIncidentAction < ApplicationRecord
  attribute :contributor_snapshot, :json
  belongs_to :vps
  belongs_to :user
  belongs_to :incident_policy_evaluation
  belongs_to :stop_owner_action, class_name: 'VpsIncidentAction', optional: true
  belongs_to :incident_report
  belongs_to :notice_incident_report, class_name: 'IncidentReport', optional: true
  belongs_to :transaction_chain, optional: true
  belongs_to :mail_chain, class_name: 'TransactionChain', optional: true
  belongs_to :mail_log, optional: true

  scope :outstanding_stops, -> { where(kind: 'stop', state: %w[pending queued failed uncertain]) }

  def saved_policy_evaluation
    contributor_snapshot&.fetch('policy', nil) || incident_policy_evaluation&.snapshot
  end

  def message_id
    "<vps-incident-action-#{id}@vpsadmin>"
  end
end
