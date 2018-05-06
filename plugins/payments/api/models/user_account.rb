require 'date'

class UserAccount < ActiveRecord::Base
  belongs_to :user
  before_validation :set_defaults

  include Lockable

  class AccountDisabled < StandardError ; end

  # Accept queued payments
  def self.accept_payments
    transaction do
      ::IncomingPayment.where(
          state: ::IncomingPayment.states[:queued],
      ).each do |income|
        begin
          u = ::User.find(income.vs.to_i)

        rescue ActiveRecord::RecordNotFound
          income.update!(state: ::IncomingPayment.states[:unmatched])
          next
        end

        begin
          _, payment = accept_payment(u, income)

        rescue ::ResourceLocked
          next
        end

        unless payment
          income.update!(state: ::IncomingPayment.states[:unmatched])
          next
        end
      end
    end
  end

  # @param user [User]
  # @param income [IncomingPayment]
  def self.accept_payment(user, income)
    payment = ::UserPayment.new(
      incoming_payment: income,
      user: user,
    )
    amount = income.converted_amount

    # Break if we're unable to figure out the received amount
    return if amount.nil?

    # Break if the received amount is not a multiple of the monthly payment
    return if amount % user.user_account.monthly_payment != 0

    payment.amount = amount

    VpsAdmin::API::Plugins::Payments::TransactionChains::Create.fire(payment)

  rescue ::UserAccount::AccountDisabled
    return
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
