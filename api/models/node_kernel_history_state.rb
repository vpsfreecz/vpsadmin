class NodeKernelHistoryState < ApplicationRecord
  belongs_to :node
  has_many :kernel_history_gaps,
           class_name: 'NodeKernelHistoryGap',
           dependent: :delete_all,
           inverse_of: :node_kernel_history_state

  validates :node_id, uniqueness: true
  validates :completed_at, presence: true
end
