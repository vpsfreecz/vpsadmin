module VpsAdmin::API::Plugins::Payments::TransactionChains
  class MailOverview < ::TransactionChain
    label 'Payments overview notifications'

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
        incoming: income
      }

      ::IncomingPayment.states.each_key do |k|
        vars[k.to_sym] = income.where(state: ::IncomingPayment.states[k])
      end

      vars[:accepted] = ::UserPayment.where(
        'DATE_ADD(created_at, INTERVAL ? SECOND) >= ?', period, t
      ).order('user_payments.created_at, user_payments.user_id')

      event = route_event!(
        'payments.overview',
        subject: 'Payments overview',
        summary: "Payments overview from #{format_report_time(now - period)} to #{format_report_time(now)}",
        payload: report_parameters(period, language, now, income, vars[:accepted]),
        report_vars: vars
      )
      ensure_email_deliveries_queued!(event)
    end

    protected

    def report_parameters(period, language, now, income, accepted)
      {
        language_id: language.id,
        language_code: language.code,
        period_start: format_report_time(now - period),
        period_end: format_report_time(now),
        period_seconds: period,
        incoming_payment_count: income.count,
        accepted_payment_count: accepted.count
      }
    end

    def format_report_time(time)
      time.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
    end

    def ensure_email_deliveries_queued!(event)
      failed = event
               .event_deliveries
               .where(action: 'email', state: 'failed')
               .order(:id)
               .first
      raise "failed to queue payments overview e-mail delivery: #{failed.error_summary}" if failed

      pending = event.event_deliveries.where(action: 'email', state: 'planned').order(:id).first
      pending ||= event
                  .event_deliveries
                  .where(action: 'email', state: 'queued', transaction_id: nil)
                  .order(:id)
                  .first
      return unless pending

      raise "failed to queue payments overview e-mail delivery: #{pending.error_summary || pending.state}"
    end
  end
end
