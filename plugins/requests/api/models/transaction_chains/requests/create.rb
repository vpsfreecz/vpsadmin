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
        action: 'create',
        recipient_email: request.user_mail
      )
    end
  end
end
