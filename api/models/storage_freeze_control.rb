class StorageFreezeControl < ApplicationRecord
  belongs_to :active_maintenance_run, class_name: 'StorageMaintenanceRun', optional: true

  enum :mode, %i[read_write read_only]

  validates :id, inclusion: { in: [1] }, if: :persisted?
  validates :epoch, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.singleton!
    find(1)
  end
end
