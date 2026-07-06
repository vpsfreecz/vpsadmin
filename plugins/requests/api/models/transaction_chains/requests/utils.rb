module VpsAdmin::API::Plugins::Requests::TransactionChains
  module Utils
    def message_id(r, mail_id = nil)
      format(::SysConfig.get(:plugin_requests, :message_id), id: r.id, mail_id: mail_id || r.last_mail_id)
    end

    def route_request_event!(event_type, request, action:, mail_id: request.last_mail_id,
                             reply_to_mail_id: nil, state: request.state, reason: nil,
                             recipient_email: nil)
      action = action.to_s
      payload = request_event_parameters(
        request,
        action:,
        state:,
        mail_id:,
        reply_to_mail_id:,
        reason:,
        recipient_email:
      )

      route_event!(
        event_type,
        user: request_event_user(request, state),
        source: request,
        subject: request_event_subject(request, action),
        summary: request_event_summary(request, action, state, reason),
        payload:
      )
    end

    def request_event_user(request, state)
      return if request.is_a?(::RegistrationRequest)
      return if state.to_sym == :ignored

      request.user
    end

    def request_event_parameters(request, action:, state:, mail_id:,
                                 reply_to_mail_id:, reason:, recipient_email:)
      {
        action:,
        request_id: request.id,
        request_type: request.type_name,
        request_state: state.to_s,
        request_label: request.label,
        user_id: request.user_id,
        user_login: request.user&.login,
        recipient_email:,
        admin_id: ::User.current&.id,
        admin_login: ::User.current&.login,
        reason:,
        mail_id:,
        reply_to_mail_id:
      }.compact
    end

    def request_event_subject(request, action)
      "Request ##{request.id} #{request.type_name} #{action}"[0, 255]
    end

    def request_event_summary(request, action, state, reason)
      ret = "#{request.label} request #{action}; state #{state}"
      ret += ": #{reason}" if reason.present?
      ret
    end
  end
end
