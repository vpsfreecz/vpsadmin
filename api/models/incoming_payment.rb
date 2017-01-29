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
