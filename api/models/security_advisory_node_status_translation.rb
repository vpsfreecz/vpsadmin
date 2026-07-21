class SecurityAdvisoryNodeStatusTranslation < ApplicationRecord
  belongs_to :security_advisory_node_status
  belongs_to :language

  validates :security_advisory_node_status, :language, presence: true
  validates :language_id, uniqueness: { scope: :security_advisory_node_status_id }
end
