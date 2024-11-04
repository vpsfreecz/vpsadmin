class OsFamily < ApplicationRecord
  has_many :os_templates, dependent: :restrict_with_exception

  validates :label, presence: true
end
