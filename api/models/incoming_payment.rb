class IncomingPayment < ActiveRecord::Base
  enum state: %i(queued unmatched processed ignored)

  def converted_amount
    if src_amount
      rates = ::SysConfig.get(:plugin_payments, :conversion_rates)
      rate = rates[ src_currency.downcase ]

      return src_amount * rate if rate

    else
      return amount
    end

    nil
  end
end

TransactionChains::Mail::DailyReport.connect_hook(:send) do |ret, from, now|
  t = now.strftime('%Y-%m-%d %H:%M:%S')

  income = ::IncomingPayment.where(
      'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
  ).order('incoming_payments.created_at, incoming_payments.id')

  ret[:payments] ||= {}

  ::IncomingPayment.states.each_key do |k|
    ret[:payments][k.to_sym] = income.where(state: ::IncomingPayment.states[k])
  end

  ret
end
