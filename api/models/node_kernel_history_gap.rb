class NodeKernelHistoryGap < ApplicationRecord
  belongs_to :node_kernel_history_state, inverse_of: :kernel_history_gaps
  has_one :node, through: :node_kernel_history_state

  validates :from, :to, :reason, presence: true
end
