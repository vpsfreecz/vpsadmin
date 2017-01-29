module VpsAdmin::API::Plugins::Payments::TransactionChains
  class Create < ::TransactionChain
    label 'Create'
    allow_empty

    def link_chain(payment)
      u = payment.user
      delta = payment.amount / u.user_account.monthly_payment

      if u.user_account.paid_until
        payment.from_date = u.user_account.paid_until
        u.user_account.paid_until = add_months(u.user_account.paid_until, delta)

      else
        now = Time.now
        payment.from_date = now
        u.user_account.paid_until = add_months(now, delta)
      end

      payment.to_date = u.user_account.paid_until
      payment.save!
      u.user_account.save!
      u.set_expiration(
          payment.to_date,
          reason: "Payment ##{payment.id} accepted."
      )

      if payment.incoming_payment
        payment.incoming_payment.update!(
            state: ::IncomingPayment.states[:processed],
        )
      end
      
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

      payment
    end

    protected
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
