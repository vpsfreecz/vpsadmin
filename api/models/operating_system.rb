class OperatingSystem < ApplicationRecord
  has_many :os_families
  has_many :vpses

  validates :name, :label, presence: true
end
