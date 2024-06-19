class Language < ApplicationRecord
  has_many :users
  has_many :mail_template_translations
end
