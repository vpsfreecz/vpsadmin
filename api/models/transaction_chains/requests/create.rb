module VpsAdmin::API::Plugins::Requests::TransactionChains
  class Create < ::TransactionChain
    label 'Create'
    allow_empty

    def link_chain(request)
      concerns(:affect, [request.class.name, request.id])

      webui_url = ::SysConfig.get(:webui, :base_url)
     
      [
          :"request_create_user_#{request.type_name}",
          :request_create_user,
      ].each do |t|
        begin
          mail(t, {
              user: request.user,
              to: [request.user_mail],
              language: request.user_language,
              message_id: "<vpsadmin-request-#{request.id}-#{request.last_mail_id}@vpsadmin.vpsfree.cz>",
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
      
      ::User.where('level > 90').each do |admin|
        [
            :"request_create_admin_#{request.type_name}",
            :request_create_admin,
        ].each do |t|
          begin
            mail(t, {
                user: admin,
                message_id: "<vpsadmin-request-#{request.id}-#{request.last_mail_id}@vpsadmin.vpsfree.cz>",
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
