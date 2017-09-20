class NodePubkey < ActiveRecord::Base
  self.primary_keys = %i(node_id key_type)
  belongs_to :node

  validates :node_id, :key, presence: true
  validates :key_type, presence: true, inclusion: {in: %w(rsa dsa)}
end
