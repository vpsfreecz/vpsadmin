VpsAdmin::API::Plugin.register(:payments) do
  name 'Payments'
  description 'Adds support for monthly payments'
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    #SysConfig.register :plugin_payments, :default_currency, String
    #SysConfig.register :plugin_payments, :conversion_rates, String
    SysConfig.register :plugin_payments, :api_token, String,
        label: 'API token', min_user_level: 99
  end
end
