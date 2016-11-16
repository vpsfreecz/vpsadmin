class UserPublicKey < ActiveRecord::Base
  belongs_to :user

  validates :label, :key, presence: true
end
