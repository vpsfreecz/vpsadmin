class OsFamily < ApplicationRecord
  belongs_to :os
  has_many :os_templates, dependent: :restrict_with_exception
  has_many :vpses, dependent: :restrict_with_exception

  validates :label, presence: true
end
