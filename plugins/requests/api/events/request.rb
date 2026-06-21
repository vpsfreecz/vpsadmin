module VpsAdmin::API::Plugins::Requests::Events
  REQUEST_TEMPLATE_CANDIDATES = {
    'request.created' => %i[
      request_action_role_type
      request_action_role
    ],
    'request.updated' => %i[
      request_action_role_type
      request_action_role
    ],
    'request.resolved' => %i[
      request_resolve_role_type_state
      request_action_role_type
      request_resolve_role_state
      request_action_role
    ]
  }.freeze

  module_function

  def param(event, name)
    params = event.parameters || {}
    params[name.to_s] || params[name.to_sym]
  end

  def request_source(event)
    source = event.source
    return unless source.is_a?(::UserRequest)
    return unless request_visible_to_event_user?(event, source)

    source
  end

  def request_from_parameters(event)
    request_id = param(event, 'request_id')
    return if request_id.blank?

    request = ::UserRequest.find_by(id: request_id)
    return unless request && request_visible_to_event_user?(event, request)

    request
  end

  def request_visible_to_event_user?(event, request)
    role = param(event, 'role').to_s

    if role == 'admin'
      event.user&.role == :admin
    elsif event.user_id.blank?
      recipient = param(event, 'recipient_email')
      recipient.present? && recipient == request.user_mail
    else
      request.user_id == event.user_id
    end
  end

  def request_email_vars(event)
    request = request_source(event) || request_from_parameters(event)
    raise ArgumentError, 'request source is missing' unless request

    {
      request:,
      r: request,
      webui_url: VpsAdmin::API::Events.webui_url
    }
  end

  def request_template_name_for(event)
    params = request_template_params(event)
    language = request_email_language(event)

    REQUEST_TEMPLATE_CANDIDATES.fetch(event.event_type).find do |candidate|
      VpsAdmin::API::Events.template_available?(candidate, params, language)
    end || REQUEST_TEMPLATE_CANDIDATES.fetch(event.event_type).first
  end

  def request_template_params(event)
    {
      action: param(event, 'action'),
      role: param(event, 'role'),
      type: param(event, 'request_type'),
      state: param(event, 'request_state')
    }
  end

  def request_email_language(event)
    return event.user&.language unless param(event, 'role').to_s == 'user'

    request = request_source(event) || request_from_parameters(event)
    request&.user_language || event.user&.language
  end

  def request_message_id(event, key)
    mail_id = param(event, key)
    request_id = param(event, 'request_id')
    return if request_id.blank? || mail_id.blank?

    format(::SysConfig.get(:plugin_requests, :message_id), id: request_id, mail_id:)
  rescue StandardError
    nil
  end

  def request_template_options(event)
    ret = {
      language: request_email_language(event),
      message_id: request_message_id(event, 'mail_id')
    }.compact
    reply_to = request_message_id(event, 'reply_to_mail_id')
    if reply_to
      ret[:in_reply_to] = reply_to
      ret[:references] = reply_to
    end
    ret
  end

  def default_email_target(event)
    return unless param(event, 'role').to_s == 'user'

    param(event, 'recipient_email')
  end
end

VpsAdmin::API::Events.define owner: :requests do
  {
    'request.created' => ['Request created', { mail_id: 'Request mail thread ID' }],
    'request.updated' => ['Request updated', {
      mail_id: 'Request mail thread ID',
      reply_to_mail_id: 'Previous request mail thread ID'
    }],
    'request.resolved' => ['Request resolved', {
      admin_id: 'Resolving admin user ID',
      admin_login: 'Resolving admin login',
      reason: 'Resolution reason',
      mail_id: 'Request mail thread ID',
      reply_to_mail_id: 'Previous request mail thread ID'
    }]
  }.each do |event_name, (label, extra_parameters)|
    event event_name,
          label:,
          category: 'requests',
          severity: :info,
          default_routed: true do
      parameters(
        {
          action: 'Request action',
          role: 'Recipient role',
          request_id: 'Request ID',
          request_type: 'Request type',
          request_state: 'Request state',
          request_label: 'Request label',
          user_id: 'Request owner user ID',
          user_login: 'Request owner login',
          recipient_email: 'Recipient e-mail'
        }.merge(extra_parameters)
      )

      deliver :email do
        template { VpsAdmin::API::Plugins::Requests::Events.request_template_name_for(event) }
        params { VpsAdmin::API::Plugins::Requests::Events.request_template_params(event) }
        options { VpsAdmin::API::Plugins::Requests::Events.request_template_options(event) }
        default_target { VpsAdmin::API::Plugins::Requests::Events.default_email_target(event) }
        vars { VpsAdmin::API::Plugins::Requests::Events.request_email_vars(event) }
      end
    end
  end
end
