module VpsAdmin::API::Plugins::Payments::Events
  PaymentInfo = Struct.new(
    :id,
    :amount,
    :from_date,
    :to_date,
    :received_amount,
    :received_currency,
    :incoming_payment_id
  )

  module_function

  def param(event, name)
    params = event.payload || {}
    params[name.to_s] || params[name.to_sym]
  end

  def find_from_parameters(event, model, key)
    value = param(event, key)
    return if value.blank?

    scope = model.all
    scope = scope.where(user_id: event.user_id) if event.user_id.present? && model.column_names.include?('user_id')
    scope.find_by(id: value)
  end

  def payment_source(event)
    source = event.source
    return unless source.is_a?(::UserPayment)
    return if event.user_id.present? && source.user_id != event.user_id

    source
  end

  def payment_from_parameters(event)
    payment = find_from_parameters(event, ::UserPayment, 'payment_id')
    return payment if payment

    PaymentInfo.new(
      param(event, 'payment_id'),
      param(event, 'amount'),
      VpsAdmin::API::Events.parse_time(param(event, 'from_date')),
      VpsAdmin::API::Events.parse_time(param(event, 'to_date')),
      param(event, 'received_amount'),
      param(event, 'received_currency'),
      param(event, 'incoming_payment_id')
    )
  end

  def payment_accepted_email_vars(event)
    payment = payment_source(event) || payment_from_parameters(event)
    raise ArgumentError, 'payment source is missing' unless payment

    {
      user: event.user,
      account: event.user&.user_account,
      payment:
    }
  end

  def system_report_language(event)
    language = ::Language.find_by(id: param(event, 'language_id'))
    language ||= ::Language.find_by(code: param(event, 'language_code'))
    language || ::Language.take
  end
end

VpsAdmin::API::Events.define owner: :payments do
  event 'payment.accepted',
        label: 'Payment accepted',
        category: 'payments',
        severity: :info,
        roles: %i[account],
        default_routed: true do
    fields(
      payment_id: { description: 'ID of the accepted user payment', type: :integer },
      amount: { description: 'Amount credited to the user account', type: :number },
      received_amount: { description: 'Amount received from the incoming payment', type: :number },
      received_currency: { description: 'Currency received from the incoming payment', type: :string },
      from_date: { description: 'Beginning of the paid membership period', type: :datetime },
      to_date: { description: 'End of the paid membership period', type: :datetime },
      incoming_payment_id: { description: 'ID of the incoming payment row', type: :integer },
      incoming_transaction_id: { description: 'Bank transaction identifier of the incoming payment', type: :string },
      accounted_by_id: { description: 'ID of the admin who accounted the payment', type: :integer },
      accounted_by_login: { description: 'Login of the admin who accounted the payment', type: :string }
    )

    deliver :email do
      template :payment_accepted
      vars { VpsAdmin::API::Plugins::Payments::Events.payment_accepted_email_vars(event) }
    end
  end

  event 'payments.overview',
        label: 'Payments overview',
        category: 'payments',
        severity: :info,
        roles: %i[admin],
        default_routed: true do
    argument :report_vars, type: Hash, optional: true

    fields(
      language_id: { description: 'ID of the language used for the report', type: :integer },
      language_code: { description: 'Language code used for the report', type: :string },
      period_start: { description: 'Beginning of the report period', type: :datetime },
      period_end: { description: 'End of the report period', type: :datetime },
      period_seconds: { description: 'Length of the report period in seconds', type: :integer },
      incoming_payment_count: { description: 'Number of incoming payments included in the report', type: :integer },
      accepted_payment_count: { description: 'Number of accepted payments included in the report', type: :integer }
    )

    deliver :email do
      template { event.user_id.blank? ? :payments_overview : nil }
      system_template { event.user_id.blank? }
      vars { respond_to?(:report_vars) ? report_vars : {} }
      options do
        if event.user_id.blank?
          { language: VpsAdmin::API::Plugins::Payments::Events.system_report_language(event) }
        else
          {}
        end
      end
    end
  end
end
