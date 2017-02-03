VpsAdmin::API::Plugin.register(:requests) do
  name 'Requests'
  description 'User requests'
  version '0.1.0'
  author 'Jakub Skokan'
  email 'jakub.skokan@vpsfree.cz'
  components :api

  config do
    SysConfig.register :plugin_requests, :message_id, String,
        default: '<vpsadmin-request-%{id}-%{mail_id}@vpsadmin.vpsfree.cz>',
        label: 'Message ID',
        description: 'Mail header Message-ID used to put e-mails into threads',
        min_user_level: 99
    SysConfig.register :plugin_requests, :currencies, String, default: 'eur,czk',
        label: 'Currencies',
        description: 'Comma separated list of accepted currencies in registration',
        min_user_level: 99
    
    vars = {
        request: '::UserRequest',
        r: '::UserRequest',
        webui_url: String,
    }

    %w(user admin).each do |role|
      # Creation
      MailTemplate.register :"request_create_#{role}_type",
          name: "request_create_#{role}_%{type}", params: {
          type: 'registration or change',
          }, vars: vars
      
      MailTemplate.register :"request_create_#{role}", vars: vars

      # Resolving
      MailTemplate.register :"request_resolve_#{role}_type_state",
          name: "request_resolve_#{role}_%{type}_%{state}", params: {
              type: 'registration or change',
              state: 'one of awaiting, approved, denied, ignored'
          }, vars: vars
      
      MailTemplate.register :"request_resolve_#{role}_type",
          name: "request_resolve_#{role}_%{type}", params: {
              type: 'registration or change',
          }, vars: vars

      MailTemplate.register :"request_resolve_#{role}_state",
          name: "request_resolve_#{role}_%{state}", params: {
              state: 'one of awaiting, approved, denied, ignored'
          }, vars: vars
      
      MailTemplate.register :"request_resolve_#{role}", vars: vars
    end
  end
end
