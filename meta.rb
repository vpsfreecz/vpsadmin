VpsAdmin::API::Plugin.register(:outage_reports) do
  name 'Outage reports'
  description 'Adds support for outage reporting and mailing affected users'
  version '2.9.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :plugin_outage_reports, :announce_message_id, String,
        default: '<vpsadmin-outage-%{outage_id}-%{user_id}-announce@vpsadmin.vpsfree.cz>',
        label: 'Announce message ID',
        description: 'Mail header Message-ID used to put e-mails into threads',
        min_user_level: 99
    SysConfig.register :plugin_outage_reports, :update_message_id, String,
        default: '<vpsadmin-outage-%{outage_id}-%{user_id}-update-%{update_id}@vpsadmin.vpsfree.cz>',
        label: 'Update message ID',
        description: 'Mail header Message-ID used to put e-mails into threads',
        min_user_level: 99

    ::MailTemplate.register :outage_report_role_event,
        name: "outage_report_%{role}_%{event}", params: {
            role: 'user or generic',
            event: 'announce, cancel, close or update',
        }, roles: %i(admin), vars: {
              outage: '::Outage',
              o: '::Outage',
              update: '::OutageUpdate',
              user: '::User',
              vpses: 'Array<::Vps>',
            }, public: true

    ::MailTemplate.register :outage_report_role,
        name: "outage_report_%{role}", params: {
            role: 'user or generic',
        }, roles: %i(admin), vars: {
            outage: '::Outage',
            o: '::Outage',
            update: '::OutageUpdate',
            user: '::User',
            vpses: 'OutageVps relation',
        }, public: true
  end
end
