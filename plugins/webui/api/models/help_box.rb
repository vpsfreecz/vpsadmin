class HelpBox < ApplicationRecord
  belongs_to :language

  validates :content, presence: true
end
