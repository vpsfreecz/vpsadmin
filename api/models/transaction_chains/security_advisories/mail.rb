module TransactionChains
  module SecurityAdvisories
    class Mail < ::TransactionChain
      label 'Security advisory mail'
      allow_empty

      def link_chain(advisory, event, update = nil)
        concerns(:affect, [advisory.class.name, advisory.id])

        advisory.security_advisory_users.includes(:user).joins(:user).where(
          users: {
            object_state: [
              ::User.object_states[:active],
              ::User.object_states[:suspended]
            ],
            mailer_enabled: true
          }
        ).each do |row|
          send_mail(advisory, row.user, event, update)
        end

        advisory
      end

      protected

      def send_mail(advisory, user, event, update)
        mail(:"security_advisory_user_#{event}", {
               user:,
               vars: {
                 advisory:,
                 a: advisory,
                 update:,
                 user:,
                 vpses: advisory.security_advisory_vpses.where(user:),
                 webui_url: webui_url
               }
             })
      end

      def webui_url
        (::SysConfig.get(:webui, :base_url) || '').chomp('/')
      rescue StandardError
        ''
      end
    end
  end
end
