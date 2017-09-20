class HelpBox < ActiveRecord::Base
  belongs_to :language

  validates :content, presence: true
end
