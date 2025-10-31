class OsFamily < ApplicationRecord
  belongs_to :operating_system
  has_many :os_templates, dependent: :restrict_with_exception

  validates :label, presence: true
end
