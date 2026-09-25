class StorageIntegrityScope < ApplicationRecord
  attr_readonly :pool_catalog_id, :dataset_in_pool_catalog_id, :scope_key
  belongs_to :pool, optional: true
  belongs_to :dataset_in_pool, optional: true
  has_many :storage_observation_runs
  has_many :storage_mutation_intent_scopes

  enum :state, %i[unverified verified needs_reconcile]

  validates :scope_key, presence: true, uniqueness: true
  validates :pool_catalog_id, presence: true
  validates :mutation_epoch, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :scope_matches_owner
  before_validation :remember_catalog_ids

  private

  def scope_matches_owner
    if dataset_in_pool_catalog_id
      if dataset_in_pool && dataset_in_pool.id != dataset_in_pool_catalog_id
        errors.add(:dataset_in_pool_catalog_id, 'must match the live dataset in pool')
      end
      if dataset_in_pool && dataset_in_pool.pool_id != pool_catalog_id
        errors.add(:pool, 'must own the dataset in pool')
      end
      expected_key = "dip:#{dataset_in_pool_catalog_id}"
    else
      expected_key = "pool:#{pool_catalog_id}"
    end

    errors.add(:pool, 'must match the catalog ID') if pool && pool.id != pool_catalog_id
    errors.add(:scope_key, "must be #{expected_key}") if scope_key != expected_key
  end

  def remember_catalog_ids
    self.pool_catalog_id ||= pool_id
    self.dataset_in_pool_catalog_id ||= dataset_in_pool_id
  end
end
