class StorageMutationIntent < ApplicationRecord
  attr_readonly :node_catalog_id, :token, :manifest_digest
  belongs_to :storage_transaction,
             class_name: 'Transaction',
             foreign_key: :transaction_id,
             optional: true
  belongs_to :transaction_chain, optional: true
  belongs_to :node, optional: true
  has_many :storage_mutation_attempts
  has_many :storage_mutation_targets
  has_many :storage_mutation_intent_scopes

  enum :phase, %i[prepared executing verified rolled_back failed needs_reconcile
                  settled_unverified]

  validates :token, :kind, :manifest_digest, presence: true
  validates :node_catalog_id, presence: true
  validates :token, uniqueness: true
  validates :protocol_version, numericality: { only_integer: true, greater_than: 0 }
  validate :node_catalog_id_matches_live_node
  before_validation :remember_node_id

  private

  def remember_node_id
    self.node_catalog_id ||= node_id
  end

  def node_catalog_id_matches_live_node
    return unless node && node_catalog_id != node.id

    errors.add(:node_catalog_id, 'must match the live node')
  end
end
