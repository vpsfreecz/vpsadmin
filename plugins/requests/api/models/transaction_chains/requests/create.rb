require_relative 'utils'

module VpsAdmin::API::Plugins::Requests::TransactionChains
  class Create < ::TransactionChain
    include Utils

    label 'Creation'
    allow_empty

    def link_chain(request)
      concerns(:affect, [request.class.name, request.id])

      route_request_event!(
        'request.created',
        request,
        recipient: request.user,
        role: 'user',
        action: 'create',
        recipient_email: request.user_mail
      )

      admin_request_recipients(group_email: true).each do |admin|
        route_request_event!(
          'request.created',
          request,
          recipient: admin,
          role: 'admin',
          action: 'create'
        )
      end
    end
  end
end
