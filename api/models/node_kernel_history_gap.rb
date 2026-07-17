class NodeKernelHistoryGap < ApplicationRecord
  belongs_to :node_kernel_history_state, inverse_of: :kernel_history_gaps

  validates :from, :to, :reason, presence: true
end
