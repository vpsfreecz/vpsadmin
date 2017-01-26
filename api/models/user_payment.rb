require 'date'

class UserPayment < ActiveRecord::Base
  belongs_to :incoming_payment
  belongs_to :user

  validates :incoming_payment_id, :user_id, :amount, :from_date, :to_date,
      presence: true

  # @param payment [IncomingPayment]
  def self.accept(payment)
    transaction do
      u = ::User.find(payment.vs.to_i)
      user_payment = new(
          incoming_payment: payment,
          user: u,
      )
      amount = nil

      if payment.src_amount
        case payment.src_currency
        when 'EUR'
          amount = payment.src_amount * 25
        end

      else
        amount = payment.amount
      end

      # Break if we're unable to figure out the received amount
      next if amount.nil?

      # Break if the received amount is not a multiple of the monthly payment
      next if amount % u.monthly_payment != 0

      delta = amount / u.monthly_payment

      if u.paid_until
        user_payment.from_date = u.paid_until
        u.paid_until = add_months(u.paid_until, delta)

      else
        now = Time.now
        user_payment.from_date = now
        u.paid_until = add_months(now, delta)
      end

      user_payment.amount = amount
      user_payment.to_date = u.paid_until

      u.save!
      user_payment.save!
      payment.update!(state: 'processed')
      user_payment
    end

  rescue ActiveRecord::RecordNotFound
    # Nothing to do
  end

  # @param time [Time]
  # @param n [Integer] months to add
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
