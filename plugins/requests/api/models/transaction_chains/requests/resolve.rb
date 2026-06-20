require_relative 'utils'

module VpsAdmin::API::Plugins::Requests::TransactionChains
  class Resolve < ::TransactionChain
    include Utils

    label 'Resolve'
    allow_empty

    def link_chain(request, state, action, reason, params)
      concerns(:affect, [request.class.name, request.id])

      reply_to = request.last_mail_id

      params.each do |k, v|
        request.send("#{k}=", v) if request.class.attribute_names.include?(k.to_s)
      end

      request.update!(
        state: ::UserRequest.states[state],
        admin: ::User.current,
        admin_response: reason,
        last_mail_id: request.last_mail_id + 1
      )

      if state != :ignored
        route_request_event!(
          'request.resolved',
          request,
          recipient: request.user,
          role: 'user',
          action: 'resolve',
          reply_to_mail_id: reply_to,
          state:,
          reason:,
          recipient_email: request.user_mail
        )
      end

      admin_request_recipients.each do |admin|
        route_request_event!(
          'request.resolved',
          request,
          recipient: admin,
          role: 'admin',
          action: 'resolve',
          reply_to_mail_id: reply_to,
          state:,
          reason:
        )
      end

      request.send(action, self, params)
    end
  end
end
