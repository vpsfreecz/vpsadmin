require_relative 'utils'

module VpsAdmin::API::Plugins::Requests::TransactionChains
  class Resolve < ::TransactionChain
    include Utils

    label 'Resolve'
    allow_empty

    def link_chain(request, state, action, reason, params)
      concerns(:affect, [request.class.name, request.id])

      reply_to = request.last_mail_id
      webui_url = ::SysConfig.get(:webui, :base_url)

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
        [
          [
            :request_resolve_role_type_state,
            { role: 'user', type: request.type_name, state: }
          ],
          [
            :request_action_role_type,
            { action: 'resolve', role: 'user', type: request.type_name }
          ],
          [
            :request_resolve_role_state,
            { role: 'user', state: }
          ],
          [
            :request_action_role,
            { action: 'resolve', role: 'user' }
          ]
        ].each do |id, params|
          mail(id, {
                 params:,
                 user: request.user,
                 to: [request.user_mail],
                 language: request.user_language,
                 message_id: message_id(request),
                 in_reply_to: message_id(request, reply_to),
                 references: message_id(request, reply_to),
                 vars: {
                   request:,
                   r: request,
                   webui_url:
                 }
               })
          break
        rescue VpsAdmin::API::Exceptions::MailTemplateDoesNotExist
          next
        end
      end

      ::User.where('level > 90').where(mailer_enabled: true).each do |admin|
        [
          [
            :request_resolve_role_type_state,
            { role: 'admin', type: request.type_name, state: }
          ],
          [
            :request_action_role_type,
            { action: 'resolve', role: 'admin', type: request.type_name }
          ],
          [
            :request_resolve_role_state,
            { role: 'admin', state: }
          ],
          [
            :request_action_role,
            { action: 'resolve', role: 'admin' }
          ]
        ].each do |id, params|
          mail(id, {
                 params:,
                 user: admin,
                 message_id: message_id(request),
                 in_reply_to: message_id(request, reply_to),
                 references: message_id(request, reply_to),
                 vars: {
                   request:,
                   r: request,
                   webui_url:
                 }
               })
          break
        rescue VpsAdmin::API::Exceptions::MailTemplateDoesNotExist
          next
        end
      end

      request.send(action, self, params)
    end
  end
end
