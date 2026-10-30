class VpsIncidentAction < ApplicationRecord
  belongs_to :vps
  belongs_to :user
  belongs_to :incident_report
  belongs_to :transaction_chain, optional: true
  belongs_to :mail_chain, class_name: 'TransactionChain', optional: true
  belongs_to :mail_log, optional: true

  scope :outstanding_stops, -> { where(kind: 'stop', state: %w[pending queued failed uncertain]) }

  def message_id
    "<vps-incident-action-#{id}@vpsadmin>"
  end
end
