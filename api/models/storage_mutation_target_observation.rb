class StorageMutationTargetObservation < ApplicationRecord
  belongs_to :storage_mutation_attempt
  belongs_to :storage_mutation_target

  enum :before_presence, %i[unknown present missing], prefix: :before
  enum :after_presence, %i[unknown present missing], prefix: :after

  validates :storage_mutation_target_id,
            uniqueness: { scope: :storage_mutation_attempt_id }
  validate :same_mutation_intent
  validate :receipt_is_immutable, on: :update

  private

  def same_mutation_intent
    return unless storage_mutation_attempt && storage_mutation_target
    return if storage_mutation_attempt.storage_mutation_intent_id ==
              storage_mutation_target.storage_mutation_intent_id &&
              storage_mutation_attempt.command_key == storage_mutation_target.command_key

    errors.add(:storage_mutation_target, 'must belong to the same command and intent')
  end

  def receipt_is_immutable
    errors.add(:base, 'target observation is immutable')
  end
end
