class Language < ApplicationRecord
  has_many :users
  has_many :notification_template_variants
end
