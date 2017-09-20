module VpsAdmin::API::Plugins::Requests::TransactionChains
  class Update < ::TransactionChain
    include Utils

    label 'Update'
    allow_empty

    def link_chain(request, attrs)
      concerns(:affect, [request.class.name, request.id])

      webui_url = ::SysConfig.get(:webui, :base_url)
      reply_to = request.last_mail_id
     
      request.assign_attributes(attrs)
      request.assign_attributes(
          state: ::UserRequest.states[:awaiting],
          last_mail_id: request.last_mail_id+1,
      )
      request.save!
     
      [
          [
              :request_action_role_type,
              {action: 'update', role: 'user', type: request.type_name}
          ],
          [
              :request_action_role,
              {action: 'update', role: 'user'}
          ],
      ].each do |id, params|
        begin
          mail(id, {
              params: params,
              user: request.user,
              to: [request.user_mail],
              language: request.user_language,
              message_id: message_id(request),
              in_reply_to: message_id(request, reply_to),
              references: message_id(request, reply_to),
              vars: {
                  request: request,
                  r: request,
                  webui_url: webui_url,
              },
          })
          break

        rescue VpsAdmin::API::Exceptions::MailTemplateDoesNotExist
          next
        end
      end
      
          ::User.where('level > 90').where(mailer_enabled: true).each do |admin|
        [
            [
                :request_action_role_type,
                {action: 'update', role: 'admin', type: request.type_name}
            ],
            [
                :request_action_role,
                {action: 'update', role: 'admin'}
            ],
        ].each do |id, params|
          begin
            mail(id, {
                params: params,
                user: admin,
                message_id: message_id(request),
                in_reply_to: message_id(request, reply_to),
                references: message_id(request, reply_to),
                vars: {
                    request: request,
                    r: request,
                    webui_url: webui_url,
                },
            })
            break

          rescue VpsAdmin::API::Exceptions::MailTemplateDoesNotExist
            next
          end
        end
      end
    end
  end
end
