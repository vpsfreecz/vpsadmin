class Os < ApplicationRecord
  has_many :os_families, dependent: :restrict_with_exception

  validates :name, :label, presence: true
end
