require_relative 'utils'

module VpsAdmin::API::Plugins::Requests::TransactionChains
  class Update < ::TransactionChain
    include Utils

    label 'Update'
    allow_empty

    def link_chain(request, attrs)
      concerns(:affect, [request.class.name, request.id])

      reply_to = request.last_mail_id

      request.assign_attributes(attrs)
      request.assign_attributes(
        state: ::UserRequest.states[:awaiting],
        last_mail_id: request.last_mail_id + 1
      )
      request.save!

      route_request_event!(
        'request.updated',
        request,
        recipient: request.user,
        role: 'user',
        action: 'update',
        reply_to_mail_id: reply_to,
        recipient_email: request.user_mail
      )

      admin_request_recipients.each do |admin|
        route_request_event!(
          'request.updated',
          request,
          recipient: admin,
          role: 'admin',
          action: 'update',
          reply_to_mail_id: reply_to
        )
      end
    end
  end
end
