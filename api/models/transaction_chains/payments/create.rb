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
      
      concerns(:affect, [payment.class.name, payment.id])

      if u.object_state == 'active'
        u.user_account.save!

        if payment.incoming_payment
          payment.incoming_payment.update!(
              state: ::IncomingPayment.states[:processed],
          )
        end

        u.set_expiration(
            payment.to_date,
            reason: "Payment ##{payment.id} accepted."
        )

      elsif u.object_state == 'suspended'
        u.set_object_state(
            :active,
            expiration: payment.to_date,
            reason: "Payment ##{payment.id} accepted.",
            chain: self,
        )
        
        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          t.just_create(payment)
          t.edit_before(u.user_account, paid_until: u.user_account.paid_until_was)

          u.user_account.save!
          
          if payment.incoming_payment
            t.edit(payment.incoming_payment, state: ::IncomingPayment.states[:processed])
          end
        end

      else
        raise ::UserAccount::AccountDisabled,
            "Account #{u.id} is in state #{u.object_state}, cannot add payment"
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
