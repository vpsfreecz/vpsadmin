module VpsAdmin::API::Plugins::Payments::TransactionChains
  class Create < ::TransactionChain
    label 'Create'
    allow_empty

    def link_chain(payment)
      u = payment.user
      delta = payment.amount / u.user_account.monthly_payment

      lock(u.user_account)

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
            state: ::IncomingPayment.states[:processed]
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
          chain: self
        )

        append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
          t.just_create(payment)
          t.edit_before(u.user_account, paid_until: u.user_account.paid_until_was)

          u.user_account.save!

          t.edit(payment.incoming_payment, state: ::IncomingPayment.states[:processed]) if payment.incoming_payment
        end

      else
        raise ::UserAccount::AccountDisabled,
              "Account #{u.id} is in state #{u.object_state}, cannot add payment"
      end

      route_event!(
        'payment.accepted',
        user: u,
        source: payment,
        subject: 'Payment accepted',
        summary: payment_event_summary(payment),
        parameters: payment_event_parameters(payment)
      )

      payment
    end

    protected

    def payment_event_parameters(payment)
      incoming = payment.incoming_payment
      accounted_by = payment.accounted_by

      {
        payment_id: payment.id,
        amount: payment.amount,
        received_amount: payment_amount_parameter(payment.received_amount),
        received_currency: payment.received_currency,
        from_date: payment.from_date&.iso8601,
        to_date: payment.to_date&.iso8601,
        incoming_payment_id: payment.incoming_payment_id,
        incoming_transaction_id: incoming&.transaction_id,
        accounted_by_id: accounted_by&.id,
        accounted_by_login: accounted_by&.login
      }.compact
    end

    def payment_amount_parameter(amount)
      amount.is_a?(BigDecimal) ? amount.to_s('F') : amount
    end

    def payment_event_summary(payment)
      "Accepted payment of #{payment.received_amount} " \
        "#{payment.received_currency.to_s.upcase} for account #{payment.user_id}"
    end

    # @param time [Time]
    # @param n [Integer] months to add
    # @return [Time]
    def add_months(time, n)
      local = time.localtime
      d = Date.new(local.year, local.month, local.day) >> n
      Time.new(
        d.year,
        d.month,
        d.day,
        local.hour,
        local.min,
        local.sec
      )
    end
  end
end
