require 'date'

class UserAccount < ActiveRecord::Base
  belongs_to :user
  
  def self.accept_payments
    VpsAdmin::API::Plugins::Payments::TransactionChains::Accept.fire
  end
end

class User
  has_one :user_account

  def monthly_payment
    user_account.monthly_payment
  end
  
  def paid_until
    user_account.paid_until
  end
end

User.connect_hook(:create) do |ret, user|
  ret[:objects] << ::UserAccount.create!(user: user)
  ret
end
