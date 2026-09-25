class StorageFreezeControl < ApplicationRecord
  enum :mode, %i[read_write read_only]

  validates :id, inclusion: { in: [1] }, if: :persisted?
  validates :epoch, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def self.singleton!
    find(1)
  end
end
