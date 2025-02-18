class WebauthnCredential < ApplicationRecord
  belongs_to :user

  validates :external_id, :public_key, :label, :sign_count, presence: true
  validates :label, length: { minimum: 3 }
  validates :sign_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: (2**32) - 1 }
end
