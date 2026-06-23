module VpsAdmin::API::Plugins::Requests::TransactionChains
  module Utils
    def message_id(r, mail_id = nil)
      format(::SysConfig.get(:plugin_requests, :message_id), id: r.id, mail_id: mail_id || r.last_mail_id)
    end

    def route_request_event!(event_type, request, recipient:, role:, action:, mail_id: request.last_mail_id,
                             reply_to_mail_id: nil, state: request.state, reason: nil,
                             recipient_email: nil)
      role = role.to_s
      action = action.to_s
      parameters = request_event_parameters(
        request,
        role:,
        action:,
        state:,
        mail_id:,
        reply_to_mail_id:,
        reason:,
        recipient_email:
      )

      route_event!(
        event_type,
        user: recipient,
        source: request,
        subject: request_event_subject(request, action, role),
        summary: request_event_summary(request, action, role, state, reason),
        parameters:
      )
    end

    def admin_request_recipients(group_email: false)
      scope = ::User.where('level > 90')
      return scope unless group_email

      scope.includes(:user_notification_delivery_methods)
           .to_a
           .sort_by { |admin| [admin.notification_delivery_method_enabled?('email') ? 0 : 1, admin.id] }
           .group_by(&:email)
           .map { |_email, admins| admins.first }
    end

    def request_event_parameters(request, role:, action:, state:, mail_id:,
                                 reply_to_mail_id:, reason:, recipient_email:)
      {
        action:,
        role:,
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

    def request_event_subject(request, action, role)
      "Request ##{request.id} #{request.type_name} #{action} for #{role}"[0, 255]
    end

    def request_event_summary(request, action, role, state, reason)
      ret = "#{request.label} request #{action} notification for #{role}; state #{state}"
      ret += ": #{reason}" if reason.present?
      ret
    end
  end
end
