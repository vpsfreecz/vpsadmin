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
        action: 'update',
        reply_to_mail_id: reply_to,
        recipient_email: request.user_mail
      )
    end
  end
end
