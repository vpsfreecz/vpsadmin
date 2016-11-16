class UserPublicKey < ActiveRecord::Base
  belongs_to :user
  has_paper_trail

  validates :label, :key, presence: true
end
