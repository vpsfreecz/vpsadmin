class IsoImage < ApplicationRecord
  belongs_to :storage_pool
  has_many :vpses, dependent: :restrict_with_exception
end
