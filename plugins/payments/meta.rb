VpsAdmin::API::Plugin.register(:payments) do
  name 'Payments'
  description 'Adds support for monthly payments'
  version '4.2.1'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :plugin_payments, :default_currency, String,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.plugin_payments.default_currency', default: 'Default currency'),
                       min_user_level: 99
    SysConfig.register :plugin_payments, :default_monthly_payment, Integer,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.plugin_payments.default_monthly_payment', default: 'Default monthly payment'),
                       min_user_level: 99
    SysConfig.register :plugin_payments, :conversion_rates, Hash,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.plugin_payments.conversion_rates', default: 'Currency conversion rates'),
                       min_user_level: 99

    # Regexps to find user ID from user message / message to the recipient. Each
    # regexp must contain a named capture user_id. User message is matched only
    # if there is no variable symbol.
    SysConfig.register :plugin_payments, :user_message_regexps, Array,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.plugin_payments.user_message_regexps', default: 'Payment matching patterns'),
                       min_user_level: 99

    SysConfig.register :plugin_payments, :fio_api_tokens, Array,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.plugin_payments.fio_api_tokens', default: 'API tokens'), min_user_level: 99
    SysConfig.register :plugin_payments, :payment_instructions, Hash,
                       label: VpsAdmin::API::I18n.message('sysconfig.labels.plugin_payments.payment_instructions', default: 'Payment instructions'), min_user_level: 99,
                       localized: true

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
