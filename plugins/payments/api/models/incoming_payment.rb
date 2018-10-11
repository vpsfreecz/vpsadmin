class IncomingPayment < ActiveRecord::Base
  enum state: %i(queued unmatched processed ignored)

  # Amount converted to vpsAdmin's default currency
  def converted_amount
    rates = ::SysConfig.get(:plugin_payments, :conversion_rates)

    if src_amount
      rate = rates[ src_currency.downcase ]
      return src_amount * rate if rate
    end

    default_currency = SysConfig.get(:plugin_payments, :default_currency)
    currency_downcase = currency.downcase

    if currency_downcase == default_currency.downcase
      return amount

    elsif rates[currency_downcase]
      return amount * rates[currency_downcase]
    end

    nil
  end

  # Amount sent by the user in his currency
  def received_amount
    src_amount || amount
  end

  # Currency used by the user
  def received_currency
    src_currency || currency
  end
end

TransactionChains::Mail::DailyReport.connect_hook(:send) do |ret, from, now|
  t = now.strftime('%Y-%m-%d %H:%M:%S')

  income = ::IncomingPayment.where(
    'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
  ).order('incoming_payments.created_at, incoming_payments.id')

  ret[:payments] ||= {}
  ret[:payments][:incoming] = income

  ::IncomingPayment.states.each_key do |k|
    ret[:payments][k.to_sym] = income.where(state: ::IncomingPayment.states[k])
  end

  ret
end
