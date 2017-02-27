VpsAdmin::API::Plugin.register(:outage_reports) do
  name 'Outage reports'
  description 'Adds support for outage reporting and mailing affected users'
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :plugin_outage_reports, :message_id, String,
        default: '<vpsadmin-outage-%{outage_id}-%{user_id}-%{update_id}@vpsadmin.vpsfree.cz>',
        label: 'Message ID',
        description: 'Mail header Message-ID used to put e-mails into threads',
        min_user_level: 99

    ::MailTemplate.register :outage_report_event,
        name: "outage_report_%{event}", params:  {
            event: 'announce, cancel, close or update',
        }, roles: %i(admin), vars: {
              outage: '::Outage',
              o: '::Outage',
              update: '::OutageUpdate',
              user: '::User',
              vpses: 'Array<::Vps>',
        }
    
    ::MailTemplate.register :outage_report, roles: %i(admin), vars: {
            outage: '::Outage',
            o: '::Outage',
            update: '::OutageUpdate',
            user: '::User',
            vpses: 'Array<::Vps>',
        }
  end
end
