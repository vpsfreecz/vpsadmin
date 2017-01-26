class UserPayment < ActiveRecord::Base
  belongs_to :incoming_payment
  belongs_to :user

  validates :incoming_payment_id, :user_id, :amount, :from_date, :to_date,
      presence: true
end
