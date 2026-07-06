module VpsAdmin::API::Plugins::Requests::Events
  REQUEST_TEMPLATE_CANDIDATES = {
    'request.created' => :request_action_template_candidates,
    'request.updated' => :request_action_template_candidates,
    'request.resolved' => :request_resolve_template_candidates
  }.freeze

  module_function

  def param(event, name)
    params = event.payload || {}
    params[name.to_s] || params[name.to_sym]
  end

  def request_source(event, route_context: nil, delivery: nil)
    source = event.source
    return unless source.is_a?(::UserRequest)
    return unless request_visible_to_recipient?(event, source, route_context:, delivery:)

    source
  end

  def request_from_parameters(event, route_context: nil, delivery: nil)
    request_id = param(event, 'request_id')
    return if request_id.blank?

    request = ::UserRequest.find_by(id: request_id)
    return unless request && request_visible_to_recipient?(event, request, route_context:, delivery:)

    request
  end

  def request_visible_to_recipient?(event, request, route_context: nil, delivery: nil)
    return true if request_admin_audience?(event, route_context:, delivery:)

    if event.user_id.blank?
      recipient = param(event, 'recipient_email')
      recipient.present? && recipient == request.user_mail
    else
      request.user_id == event.user_id
    end
  end

  def request_admin_audience?(event, route_context: nil, delivery: nil)
    context = route_context || VpsAdmin::API::Events.route_context_for_delivery(delivery)
    return true if context&.subject_is_admin_visible

    recipient = delivery&.recipient_user
    recipient&.role == :admin && recipient.id != event.user_id
  end

  def request_delivery_audience(event, route_context: nil, delivery: nil)
    request_admin_audience?(event, route_context:, delivery:) ? 'admin' : 'user'
  end

  def request_email_vars(event, route_context: nil, delivery: nil)
    request = request_source(event, route_context:, delivery:) ||
              request_from_parameters(event, route_context:, delivery:)
    raise ArgumentError, 'request source is missing' unless request

    {
      request:,
      r: request,
      webui_url: VpsAdmin::API::Events.webui_url
    }
  end

  def request_template_name_for(event, route_context: nil, delivery: nil)
    language = request_email_language(event, route_context:, delivery:)
    candidates = request_template_candidates(event, route_context:, delivery:)

    candidates.find do |candidate|
      VpsAdmin::API::Events.template_available?(candidate, nil, language)
    end || candidates.first
  end

  def request_template_candidates(event, route_context: nil, delivery: nil)
    method_name = REQUEST_TEMPLATE_CANDIDATES.fetch(event.event_type)
    public_send(method_name, event, route_context:, delivery:)
  end

  def request_action_template_candidates(event, route_context: nil, delivery: nil)
    action = param(event, 'action')
    audience = request_delivery_audience(event, route_context:, delivery:)
    type = param(event, 'request_type')

    [].tap do |ret|
      ret << "request_#{action}_#{audience}_#{type}" if type.present?
      ret << "request_#{action}_#{audience}"
    end.map(&:to_sym)
  end

  def request_resolve_template_candidates(event, route_context: nil, delivery: nil)
    audience = request_delivery_audience(event, route_context:, delivery:)
    type = param(event, 'request_type')
    state = param(event, 'request_state')

    [].tap do |ret|
      ret << "request_resolve_#{audience}_#{type}_#{state}" if type.present? && state.present?
      ret << "request_resolve_#{audience}_#{type}" if type.present?
      ret << "request_resolve_#{audience}_#{state}" if state.present?
      ret << "request_resolve_#{audience}"
    end.map(&:to_sym)
  end

  def request_template_params(_event)
    nil
  end

  def request_email_language(event, route_context: nil, delivery: nil)
    if request_admin_audience?(event, route_context:, delivery:)
      return delivery&.recipient_user&.language ||
             route_context&.route_owner&.language ||
             event.user&.language
    end

    request = request_source(event, route_context:, delivery:) ||
              request_from_parameters(event, route_context:, delivery:)
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

  def request_template_options(event, route_context: nil, delivery: nil)
    ret = {
      language: request_email_language(event, route_context:, delivery:),
      message_id: request_message_id(event, 'mail_id')
    }.compact
    reply_to = request_message_id(event, 'reply_to_mail_id')
    if reply_to
      ret[:in_reply_to] = reply_to
      ret[:references] = reply_to
    end
    ret
  end

  def default_email_target(event, route_context: nil, delivery: nil)
    return if request_admin_audience?(event, route_context:, delivery:)

    param(event, 'recipient_email')
  end
end

VpsAdmin::API::Events.define owner: :requests do
  {
    'request.created' => ['Request created', {
      mail_id: { description: 'ID of the mail thread used for request notification', type: :integer }
    }],
    'request.updated' => ['Request updated', {
      mail_id: { description: 'ID of the mail thread used for request notification', type: :integer },
      reply_to_mail_id: { description: 'ID of the previous mail thread this update replies to', type: :integer }
    }],
    'request.resolved' => ['Request resolved', {
      admin_id: { description: 'ID of the admin who resolved the request', type: :integer },
      admin_login: { description: 'Login of the admin who resolved the request', type: :string },
      reason: { description: 'Reason recorded when the request was resolved', type: :string },
      mail_id: { description: 'ID of the mail thread used for request notification', type: :integer },
      reply_to_mail_id: { description: 'ID of the previous mail thread this resolution replies to', type: :integer }
    }]
  }.each do |event_name, (label, extra_fields)|
    event event_name,
          label:,
          category: 'requests',
          severity: :info,
          roles: %i[account],
          default_routed: true do
      fields(
        {
          action: { description: 'Request workflow action that produced the notification', type: :string },
          request_id: { description: 'ID of the request', type: :integer },
          request_type: { description: 'Type of request being handled', type: :string },
          request_state: { description: 'Request state after the event', type: :string },
          request_label: { description: 'User-visible request label', type: :string },
          user_id: { description: 'ID of the user who owns the request', type: :integer },
          user_login: { description: 'Login of the user who owns the request', type: :string },
          recipient_email: { description: 'Custom recipient e-mail address for this request notification', type: :string }
        }.merge(extra_fields)
      )

      deliver :email do
        template do
          VpsAdmin::API::Plugins::Requests::Events.request_template_name_for(
            event,
            route_context: route_context,
            delivery: current_delivery
          )
        end
        params { VpsAdmin::API::Plugins::Requests::Events.request_template_params(event) }
        options do
          VpsAdmin::API::Plugins::Requests::Events.request_template_options(
            event,
            route_context: route_context,
            delivery: current_delivery
          )
        end
        default_target do
          VpsAdmin::API::Plugins::Requests::Events.default_email_target(
            event,
            route_context: route_context,
            delivery: current_delivery
          )
        end
        vars do
          VpsAdmin::API::Plugins::Requests::Events.request_email_vars(
            event,
            route_context: route_context,
            delivery: current_delivery
          )
        end
      end
    end
  end
end
