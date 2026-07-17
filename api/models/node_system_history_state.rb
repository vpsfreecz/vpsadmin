class NodeSystemHistoryState < ApplicationRecord
  belongs_to :node

  validates :node_id, uniqueness: true
  validates :completed_at, presence: true
end
