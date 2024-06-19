require 'date'

class UserAccount < ApplicationRecord
  belongs_to :user
  before_validation :set_defaults

  include Lockable

  class AccountDisabled < StandardError; end

  # Accept queued payments
  def self.accept_payments
    regexps = (::SysConfig.get(:plugin_payments, :user_message_regexps) || []).map do |s|
      Regexp.new(s)
    end

    transaction do
      ::IncomingPayment.where(
        state: ::IncomingPayment.states[:queued]
      ).each do |income|
        search_id = nil

        if income.vs
          search_id = income.vs
        else # no variable symbol, search by user_message
          regexps.each do |rx|
            matches = rx.match(income.user_message)
            next if matches.nil? || matches[:user_id].nil?

            search_id = matches[:user_id]
            break
          end
        end

        begin
          u = ::User.find(search_id.to_i)
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
    # Cannot handle payments from users with no monthly payment set
    return if user.user_account.monthly_payment == 0

    payment = ::UserPayment.new(
      incoming_payment: income,
      user:
    )
    amount = income.converted_amount

    # Break if we're unable to figure out the received amount
    return if amount.nil?

    # Break if the received amount is not a multiple of the monthly payment
    return if amount % user.user_account.monthly_payment != 0

    payment.amount = amount

    VpsAdmin::API::Plugins::Payments::TransactionChains::Create.fire(payment)
  rescue ::UserAccount::AccountDisabled
    nil
  end

  def payment_instructions
    ERB.new(
      SysConfig.get(:plugin_payments, :payment_instructions) || '',
      trim_mode: '-'
    ).result(binding)
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
  ret[:objects] << ::UserAccount.create!(user:)
  ret
end
