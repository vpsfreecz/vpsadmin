require_relative 'utils'

module VpsAdmin::API::Plugins::Requests::TransactionChains
  class Create < ::TransactionChain
    include Utils

    label 'Create'
    allow_empty

    def link_chain(request)
      concerns(:affect, [request.class.name, request.id])

      webui_url = ::SysConfig.get(:webui, :base_url)

      [
        [
          :request_action_role_type,
          { action: 'create', role: 'user', type: request.type_name }
        ],
        [
          :request_action_role,
          { action: 'create', role: 'user' }
        ]
      ].each do |id, params|
        mail(id, {
               params:,
               user: request.user,
               to: [request.user_mail],
               language: request.user_language,
               message_id: message_id(request),
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

      ::User.where('level > 90').where(mailer_enabled: true).group(:email).each do |admin|
        [
          [
            :request_action_role_type,
            { action: 'create', role: 'admin', type: request.type_name }
          ],
          [
            :request_action_role,
            { action: 'create', role: 'admin' }
          ]
        ].each do |id, params|
          mail(id, {
                 params:,
                 user: admin,
                 message_id: message_id(request),
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
    end
  end
end
