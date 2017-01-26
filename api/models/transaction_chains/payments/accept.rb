module VpsAdmin::API::Plugins::Payments::TransactionChains
  class Accept < ::TransactionChain
    label 'Accept'
    allow_empty

    def link_chain
      ::IncomingPayment.where(
          state: ::IncomingPayment.states[:queued],
      ).each do |income|
        begin
          u = ::User.find(income.vs.to_i)
        
        rescue ActiveRecord::RecordNotFound
          income.update!(state: ::IncomingPayment.states[:unmatched])
          next
        end

        payment = process(u, income)

        unless payment
          income.update!(state: ::IncomingPayment.states[:unmatched])
          next
        end

        income.update!(state: ::IncomingPayment.states[:processed])

        if u.mailer_enabled
          mail(:payment_accepted, {
              user: u,
              vars: {
                  user: u,
                  account: u.user_account,
                  payment: payment,
              },
          })
        end
      end
    end

    def process(u, income)
      payment = ::UserPayment.new(
          incoming_payment: income,
          user: u,
      )
      amount = nil

      if income.src_amount
        rates = ::SysConfig.get(:plugin_payments, :conversion_rates)
        rate = rates[ income.src_currency.downcase ]

        amount = income.src_amount * rate if rate

      else
        amount = income.amount
      end

      # Break if we're unable to figure out the received amount
      return if amount.nil?

      # Break if the received amount is not a multiple of the monthly payment
      return if amount % u.user_account.monthly_payment != 0

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
      payment
    end

    # @param time [Time]
    # @param n [Integer] months to add
    # @return [Time]
    def add_months(time, n)
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
end
