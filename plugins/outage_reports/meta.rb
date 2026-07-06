VpsAdmin::API::Plugin.register(:outage_reports) do
  name 'Outage reports'
  description 'Adds support for outage reporting and mailing affected users'
  version '4.1.0'
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

    outage_vars = {
      outage: '::Outage',
      o: '::Outage',
      update: '::OutageUpdate',
      user: '::User',
      vpses: 'OutageVps relation',
      direct_vpses: 'OutageVps relation',
      indirect_vpses: 'OutageVps relation',
      exports: 'OutageExport relation',
      security_advisory_cves: 'Array<Hash>',
      webui_url: String
    }

    %i[
      outage_report_generic
      outage_report_generic_announce
      outage_report_generic_update
      outage_report_user
      outage_report_user_announce
      outage_report_user_update
    ].each do |template_name|
      ::NotificationTemplate.register template_name,
                                      name: template_name.to_s,
                                      vars: outage_vars,
                                      public: true
    end
  end
end
