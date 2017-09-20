module VpsAdmin::API::Plugins::Payments::TransactionChains
  class MailOverview < ::TransactionChain
    label 'Mail overview'

    def link_chain(period, language)
      now = Time.now
      t = now.strftime('%Y-%m-%d %H:%M:%S')
      income = ::IncomingPayment.where(
          'DATE_ADD(created_at, INTERVAL ? SECOND) >= ?', period, t
      ).order('incoming_payments.created_at, incoming_payments.id')
      vars = {
          base_url: ::SysConfig.get(:webui, :base_url),
          start: now - period,
          end: now,
          incoming: income,
      }

      ::IncomingPayment.states.each_key do |k|
        vars[k.to_sym] = income.where(state: ::IncomingPayment.states[k])
      end

      vars[:accepted] = ::UserPayment.where(
          'DATE_ADD(created_at, INTERVAL ? SECOND) >= ?', period, t
      ).order('user_payments.created_at, user_payments.user_id')

      mail(:payments_overview, {
        language: language,
        vars: vars,
      })
    end
  end
end
