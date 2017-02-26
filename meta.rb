VpsAdmin::API::Plugin.register(:outage_reports) do
  name 'Outage reports'
  description 'Adds support for outage reporting and mailing affected users'
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    ::MailTemplate.register :outage_report_event,
        name: "outage_report_%{event}", params:  {
            event: 'announce, cancel, close or update',
        }, vars: {
              outage: '::Outage',
              o: '::Outage',
              update: '::OutageUpdate',
              user: '::User',
              vpses: 'Array<::Vps>',
        }
    
    ::MailTemplate.register :outage_report, vars: {
            outage: '::Outage',
            o: '::Outage',
            update: '::OutageUpdate',
            user: '::User',
            vpses: 'Array<::Vps>',
        }
  end
end
