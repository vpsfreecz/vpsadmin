class NodeSysctlChange < ApplicationRecord
  belongs_to :node_kernel_event, inverse_of: :sysctl_changes

  validates :name, presence: true, uniqueness: { scope: :node_kernel_event_id }
end
