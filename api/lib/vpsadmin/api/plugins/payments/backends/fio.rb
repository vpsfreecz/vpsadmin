require 'fio_api'

module VpsAdmin::API::Plugins::Payments::Backends
  class Fio < Base
    register :fio

    def fetch
      FioAPI.token = SysConfig.get(:plugin_payments, :api_token)
      list = FioAPI::List.new
      list.from_last_fetch
      list.response.transactions.each do |t|
        next if t.amount < 0 # Skip outgoing payments

        p = ::IncomingPayment.new(
            transaction_id: t.transaction_id.to_s,
            date: t.date,
            amount: t.amount,
            currency: t.currency,
            account_name: t.account_name,
            user_ident: t.user_identification,
            user_message: t.message_for_recipient,
            vs: t.vs,
            ks: t.ks,
            ss: t.ss,
            transaction_type: t.transaction_type,
            comment: t.comment,
        )

        if t.detail_info
          p.src_amount, p.src_currency = t.detail_info.split(' ')
        end

        p.save!

        ::UserAccount.accept_payment(p)
      end
    end
  end
end
