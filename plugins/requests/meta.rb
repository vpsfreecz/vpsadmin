VpsAdmin::API::Plugin.register(:requests) do
  name 'Requests'
  description 'User requests'
  version '3.0.0.dev'
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
    SysConfig.register :plugin_requests, :ipqs_key, String,
        min_user_level: 99

    vars = {
        request: '::UserRequest',
        r: '::UserRequest',
        webui_url: String,
    }

    %w(user admin).each do |role|
      MailTemplate.register :request_action_role_type,
          name: "request_%{action}_%{role}_%{type}", params: {
              action: 'create or resolve',
              role: 'user or admin',
              type: 'registration or change',
          }, vars: vars

      MailTemplate.register :request_action_role,
          name: "request_%{action}_%{role}", params: {
              action: 'create or resolve',
              role: 'user or admin',
          }, vars: vars

      MailTemplate.register :request_resolve_role_type_state,
          name: "request_resolve_%{role}_%{type}_%{state}", params: {
              role: 'user or admin',
              type: 'registration or change',
              state: 'one of awaiting, approved, denied, ignored'
          }, vars: vars

      MailTemplate.register :request_resolve_role_state,
          name: "request_resolve_%{role}_%{state}", params: {
              role: 'user or admin',
              state: 'one of awaiting, approved, denied, ignored'
          }, vars: vars
    end
  end
end
