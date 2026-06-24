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
    params = event.parameters || {}
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
        default_routed: true do
    parameters(
      payment_id: 'Payment ID',
      amount: 'Accounted amount',
      received_amount: 'Received amount',
      received_currency: 'Received currency',
      from_date: 'Paid from date',
      to_date: 'Paid until date',
      incoming_payment_id: 'Incoming payment ID',
      incoming_transaction_id: 'Incoming bank transaction ID',
      accounted_by_id: 'Accounting admin user ID',
      accounted_by_login: 'Accounting admin login'
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
        default_routed: true do
    argument :report_vars, type: Hash, optional: true

    parameters(
      language_id: 'Notification language ID',
      language_code: 'Notification language code',
      period_start: 'Report period start',
      period_end: 'Report period end',
      period_seconds: 'Report period in seconds',
      incoming_payment_count: 'Incoming payment count',
      accepted_payment_count: 'Accepted payment count'
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
