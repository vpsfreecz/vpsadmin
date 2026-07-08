VpsAdmin::API::Plugin.register(:requests) do
  name 'Requests'
  description 'User requests'
  version '4.1.0'
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
      webui_url: String
    }

    %w[user admin].each do |audience|
      %w[create update].each do |action|
        NotificationTemplate.register(:"request_#{action}_#{audience}", vars:)

        %w[registration change].each do |type|
          NotificationTemplate.register(
            :"request_#{action}_#{audience}_#{type}",
            vars:,
            default: false
          )
        end
      end

      NotificationTemplate.register(:"request_resolve_#{audience}", vars:)

      %w[registration change].each do |type|
        NotificationTemplate.register(
          :"request_resolve_#{audience}_#{type}",
          vars:,
          default: false
        )
      end

      %w[awaiting approved denied ignored pending_correction].each do |state|
        NotificationTemplate.register(
          :"request_resolve_#{audience}_#{state}",
          vars:,
          default: false
        )

        %w[registration change].each do |type|
          NotificationTemplate.register(
            :"request_resolve_#{audience}_#{type}_#{state}",
            vars:,
            default: false
          )
        end
      end
    end
  end
end
