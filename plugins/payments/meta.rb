VpsAdmin::API::Plugin.register(:payments) do
  name 'Payments'
  description 'Adds support for monthly payments'
  version '3.0.0.dev'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :plugin_payments, :default_currency, String,
        min_user_level: 99
    SysConfig.register :plugin_payments, :default_monthly_payment, Integer,
        min_user_level: 99
    SysConfig.register :plugin_payments, :conversion_rates, Hash,
        min_user_level: 99
    SysConfig.register :plugin_payments, :fio_api_tokens, String,
        label: 'API tokens', min_user_level: 99

    MailTemplate.register :payment_accepted, vars: {
        user: '::User',
        account: '::UserAccount',
        payment: '::UserPayment',
    }, roles: %i(account), public: true

    MailTemplate.register :payments_overview, vars: {
        base_url: [String, "URL to the web UI"],
        start: ::Time,
        end: ::Time,
        incoming: 'IncomingPayment relation',
        queued: 'IncomingPayment relation',
        unmatched: 'IncomingPayment relation',
        processed: 'IncomingPayment relation',
        ignored: 'IncomingPayment relation',
        accepted: 'UserPayment relation',
    }

    MailTemplate.register :daily_report, vars: {
        payments: Hash,
    }
  end
end
