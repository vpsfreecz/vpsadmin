class StorageObservationRun < ApplicationRecord
  belongs_to :storage_integrity_scope

  enum :state, %i[collecting complete incomplete stale]

  validates :collector_version, numericality: { only_integer: true, greater_than: 0 }
  validates :mutation_epoch, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ordered_observation_windows
  validate :complete_run_has_evidence

  private

  def ordered_observation_windows
    %i[db node].each do |source|
      from = public_send("#{source}_observed_from_at")
      until_time = public_send("#{source}_observed_until_at")
      next if from.nil? || until_time.nil? || from <= until_time

      errors.add("#{source}_observed_until_at", 'must be after capture start')
    end
  end

  def complete_run_has_evidence
    return unless complete?

    %i[db_observed_from_at db_observed_until_at node_observed_from_at
       node_observed_until_at digest].each do |attribute|
      errors.add(attribute, 'is required for a complete run') if public_send(attribute).blank?
    end
  end
end
