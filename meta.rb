VpsAdmin::API::Plugin.register(:payments) do
  name 'Payments'
  description 'Adds support for monthly payments'
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :plugin_payments, :default_currency, String,
        min_user_level: 99
    SysConfig.register :plugin_payments, :conversion_rates, Hash,
        min_user_level: 99
    SysConfig.register :plugin_payments, :api_token, String,
        label: 'API token', min_user_level: 99

    MailTemplate.register :payment_accepted, vars: {
        user: '::User',
        account: '::UserAccount',
        payment: '::UserPayment',
    }

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
