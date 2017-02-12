require 'date'

class UserAccount < ActiveRecord::Base
  belongs_to :user
  before_validation :set_defaults

  class AccountDisabled < StandardError ; end
  
  def self.accept_payments
    VpsAdmin::API::Plugins::Payments::TransactionChains::Accept.fire
  end

  protected
  def set_defaults
    return if persisted?
    self.monthly_payment = ::SysConfig.get(
        :plugin_payments,
        :default_monthly_payment
    ).to_i
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
