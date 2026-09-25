class StorageMutationTarget < ApplicationRecord
  belongs_to :storage_mutation_intent
  belongs_to :storage_mutation_intent_scope
  belongs_to :storage_filesystem_identity, optional: true
  belongs_to :snapshot_in_pool, optional: true
  belongs_to :snapshot_in_pool_in_branch, optional: true
  has_many :storage_mutation_target_observations

  validates :command_key, :kind, presence: true
  validates :sequence, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sequence, uniqueness: {
    scope: %i[storage_mutation_intent_id command_key]
  }
  validate :at_most_one_catalog_link
  validate :scope_belongs_to_intent
  validate :catalog_snapshot_matches_link
  validate :catalog_snapshot_pair
  validate :sealed_target_is_immutable, on: :update
  before_validation :remember_catalog_link

  private

  def at_most_one_catalog_link
    count = %i[storage_filesystem_identity snapshot_in_pool snapshot_in_pool_in_branch]
            .count { |name| public_send(name).present? }
    errors.add(:base, 'at most one catalog link is allowed') if count > 1
  end

  def scope_belongs_to_intent
    return unless storage_mutation_intent_scope && storage_mutation_intent
    return if storage_mutation_intent_scope.storage_mutation_intent_id == storage_mutation_intent_id

    errors.add(:storage_mutation_intent_scope, 'must belong to this intent')
  end

  def remember_catalog_link
    link = storage_filesystem_identity || snapshot_in_pool || snapshot_in_pool_in_branch
    return unless link

    self.catalog_kind ||= link.class.name
    self.catalog_id ||= link.id
  end

  def catalog_snapshot_matches_link
    link = storage_filesystem_identity || snapshot_in_pool || snapshot_in_pool_in_branch
    return unless link
    return if catalog_kind == link.class.name && catalog_id == link.id

    errors.add(:catalog_id, 'must identify the linked catalog row')
  end

  def catalog_snapshot_pair
    return if catalog_kind.nil? == catalog_id.nil?

    errors.add(:catalog_id, 'must be present together with catalog kind')
  end

  def sealed_target_is_immutable
    errors.add(:base, 'mutation target is immutable')
  end
end
