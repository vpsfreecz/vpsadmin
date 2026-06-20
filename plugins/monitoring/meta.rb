VpsAdmin::API::Plugin.register(:monitoring) do
  name 'Monitoring'
  description 'Monitors resource usage and sends alerts'
  version '4.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :plugin_monitoring, :alert_message_id, String,
                       default: '<vpsadmin-monitoring-alert-%{event_id}-%{alert_id}-%{state}@vpsadmin.vpsfree.cz>',
                       label: 'Alert message ID',
                       description: 'Mail header Message-ID used to put monitoring alert e-mails into threads',
                       min_user_level: 99
  end
end
