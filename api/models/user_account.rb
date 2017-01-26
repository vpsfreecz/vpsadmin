require 'date'

class UserAccount < ActiveRecord::Base
  belongs_to :user
  
  # @param income [IncomingPayment]
  # @return [UserPayment, nil]
  def self.accept_payment(income)
    transaction do
      u = ::User.find(income.vs.to_i)
      payment = ::UserPayment.new(
          incoming_payment: income,
          user: u,
      )
      amount = nil

      if income.src_amount
        case income.src_currency
        when 'EUR'
          amount = income.src_amount * 25
        end

      else
        amount = income.amount
      end

      # Break if we're unable to figure out the received amount
      next if amount.nil?

      # Break if the received amount is not a multiple of the monthly payment
      next if amount % u.user_account.monthly_payment != 0

      delta = amount / u.user_account.monthly_payment

      if u.user_account.paid_until
        payment.from_date = u.user_account.paid_until
        u.user_account.paid_until = add_months(u.user_account.paid_until, delta)

      else
        now = Time.now
        payment.from_date = now
        u.user_account.paid_until = add_months(now, delta)
      end

      payment.amount = amount
      payment.to_date = u.user_account.paid_until

      u.save!
      payment.save!
      u.user_account.save!
      income.update!(state: 'processed')
      payment
    end

  rescue ActiveRecord::RecordNotFound
    # Nothing to do
  end

  # @param time [Time]
  # @param n [Integer] months to add
  # @return [Time]
  def self.add_months(time, n)
    d = Date.new(time.year, time.month, time.day) >> n
    Time.new(
        d.year,
        d.month,
        d.day,
        time.hour,
        time.min,
        time.sec
    )
  end
end

class User
  has_one :user_account
end

User.connect_hook(:create) do |ret, user|
  ret[:objects] << ::UserAccount.create!(user: user)
  ret
end
