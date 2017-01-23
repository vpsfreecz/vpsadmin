module VpsAdmin::API::Plugins::Requests::TransactionChains
  class Resolve < ::TransactionChain
    label 'Resolve'
    allow_empty

    def link_chain(request, state, action, reason)
      concerns(:affect, [request.class.name, request.id])

      reply_to = request.last_mail_id

      request.update!(
          state: ::UserRequest.states[state],
          admin: ::User.current,
          admin_response: reason,
          last_mail_id: request.last_mail_id+1,
      )
     
      if state != :ignored
        [
            :"request_resolve_user_#{request.type_name}_#{state}",
            :"request_resolve_user_#{request.type_name}",
            :"request_resolve_user_#{state}",
            :request_resolve_user,
        ].each do |t|
          begin
            mail(t, {
                user: request.user,
                to: [request.user_mail],
                language: request.user_language,
                message_id: "<vpsadmin-request-#{request.id}-#{request.last_mail_id}@vpsadmin.vpsfree.cz>",
                in_reply_to: "<vpsadmin-request-#{request.id}-#{reply_to}@vpsadmin.vpsfree.cz>",
                references: "<vpsadmin-request-#{request.id}-#{reply_to}@vpsadmin.vpsfree.cz>",
                vars: {
                    request: request,
                    r: request,
                },
            })
            break

          rescue VpsAdmin::API::Exceptions::MailTemplateDoesNotExist
            next
          end
        end
      end
      
      ::User.where('level > 90').each do |admin|
        [
            :"request_resolve_admin_#{request.type_name}_state",
            :"request_resolve_admin_#{request.type_name}",
            :"request_resolve_admin_#{state}",
            :request_resolve_admin,
        ].each do |t|
          begin
            mail(t, {
                user: admin,
                message_id: "<vpsadmin-request-#{request.id}-#{request.last_mail_id}@vpsadmin.vpsfree.cz>",
                in_reply_to: "<vpsadmin-request-#{request.id}-#{reply_to}@vpsadmin.vpsfree.cz>",
                references: "<vpsadmin-request-#{request.id}-#{reply_to}@vpsadmin.vpsfree.cz>",
                vars: {
                    request: request,
                    r: request,
                },
            })
            break

          rescue VpsAdmin::API::Exceptions::MailTemplateDoesNotExist
            next
          end
        end
      end

      request.send(action, self)
    end
  end
end
