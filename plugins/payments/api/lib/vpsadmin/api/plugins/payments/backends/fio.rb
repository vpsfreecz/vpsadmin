require 'fio_api'

module VpsAdmin::API::Plugins::Payments::Backends
  class Fio < Base
    register :fio

    def fetch
      SysConfig.get(:plugin_payments, :fio_api_tokens).each do |token|
        FioAPI.token = token
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
            transaction_type: t.transaction_type || 'unset',
            comment: t.comment,
          )

          if t.detail_info
            p.src_amount, p.src_currency = t.detail_info.split(' ')
          end

          begin
            p.save!

          rescue ActiveRecord::RecordNotUnique
            warn "Duplicit transaction ID '#{t.transaction_id}'"
            next
          end
        end
      end
    end
  end
end
