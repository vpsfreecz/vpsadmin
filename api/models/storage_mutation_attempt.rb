class StorageMutationAttempt < ApplicationRecord
  belongs_to :storage_mutation_intent
  has_many :storage_mutation_target_observations

  enum :direction, %i[execute rollback], prefix: :direction
  enum :state, %i[started succeeded failed uncertain]

  validates :command_key, presence: true
  validates :attempt_number, numericality: { only_integer: true, greater_than: 0 }
  validates :attempt_number, uniqueness: {
    scope: %i[storage_mutation_intent_id command_key direction]
  }
  validate :strict_provenance_pair
  validate :strict_provenance_is_immutable, on: :update
  validate :finished_receipt_is_immutable, on: :update

  private

  def strict_provenance_pair
    return if strict_dispatch_registry_version.nil? && strict_signed_input_digest.nil?
    return if strict_dispatch_registry_version.to_i > 0 &&
              strict_signed_input_digest.to_s.match?(/\A[0-9a-f]{64}\z/)

    errors.add(:base, 'strict attempt provenance requires a version and signed input digest')
  end

  def strict_provenance_is_immutable
    return unless will_save_change_to_strict_dispatch_registry_version? ||
                  will_save_change_to_strict_signed_input_digest?

    errors.add(:base, 'strict attempt provenance is set only when the attempt starts')
  end

  def finished_receipt_is_immutable
    return if state_in_database == 'started' && !finished_at_in_database

    errors.add(:base, 'finished mutation attempt is immutable')
  end
end
