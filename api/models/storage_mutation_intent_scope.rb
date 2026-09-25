class StorageMutationIntentScope < ApplicationRecord
  belongs_to :storage_mutation_intent
  belongs_to :storage_integrity_scope
  has_many :storage_mutation_targets

  validates :storage_integrity_scope_id,
            uniqueness: { scope: :storage_mutation_intent_id }
  validates :expected_epoch,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :sealed_epoch_is_immutable, on: :update

  private

  def sealed_epoch_is_immutable
    errors.add(:base, 'intent scope is immutable')
  end
end
