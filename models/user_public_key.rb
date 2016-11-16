class UserPublicKey < ActiveRecord::Base
  belongs_to :user
  has_paper_trail

  validates :label, :key, presence: true
  validates :key, format: {
      with: /\A[^\n]+\z/,
      message: 'must not contain line breaks',
  }
end
