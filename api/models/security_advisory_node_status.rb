class SecurityAdvisoryNodeStatus < ApplicationRecord
  belongs_to :security_advisory
  belongs_to :node

  enum :state, %i[unknown not_affected vulnerable mitigated]

  validates :security_advisory, :node, presence: true
  validates :node_id, uniqueness: { scope: :security_advisory_id }
  validate :node_in_advisory_scope
  validate :mitigated_times_present

  STATE_LABELS = {
    'unknown' => 'Unknown',
    'not_affected' => 'Not affected',
    'vulnerable' => 'Vulnerable',
    'mitigated' => 'Mitigated'
  }.freeze

  def state_label
    STATE_LABELS.fetch(state, state.to_s)
  end

  protected

  def node_in_advisory_scope
    return if node.nil?
    return if SecurityAdvisory.advisory_nodes.where(id: node.id).exists?

    errors.add(:node, 'must be an active hypervisor or storage node')
  end

  def mitigated_times_present
    return unless mitigated?

    errors.add(:vulnerable_until, 'must be set for mitigated nodes') if vulnerable_until.nil?
    errors.add(:mitigated_since, 'must be set for mitigated nodes') if mitigated_since.nil?
  end
end
