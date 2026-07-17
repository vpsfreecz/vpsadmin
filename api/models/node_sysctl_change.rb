class NodeSysctlChange < ApplicationRecord
  belongs_to :node_kernel_event, inverse_of: :sysctl_changes
  has_one :node, through: :node_kernel_event
  has_one :node_kernel_evidence, through: :node_kernel_event, source: :kernel_evidence
  delegate :observed_after, :observed_before, to: :node_kernel_event

  validates :name, presence: true, uniqueness: { scope: :node_kernel_event_id }
end
