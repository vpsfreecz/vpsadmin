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

    # Regexps to find user ID from user message / message to the recipient. Each
    # regexp must contain a named capture user_id. User message is matched only
    # if there is no variable symbol.
    SysConfig.register :plugin_payments, :user_message_regexps, Array,
                       min_user_level: 99

    SysConfig.register :plugin_payments, :fio_api_tokens, Array,
                       label: 'API tokens', min_user_level: 99
    SysConfig.register :plugin_payments, :payment_instructions, Text,
                       label: 'Payment instructions', min_user_level: 99

    MailTemplate.register :payment_accepted, vars: {
      user: '::User',
      account: '::UserAccount',
      payment: '::UserPayment'
    }, roles: %i[account], public: true

    MailTemplate.register :payments_overview, vars: {
      base_url: [String, 'URL to the web UI'],
      start: ::Time,
      end: ::Time,
      incoming: 'IncomingPayment relation',
      queued: 'IncomingPayment relation',
      unmatched: 'IncomingPayment relation',
      processed: 'IncomingPayment relation',
      ignored: 'IncomingPayment relation',
      accepted: 'UserPayment relation'
    }

    MailTemplate.register :daily_report, vars: {
      payments: Hash
    }
  end
end
