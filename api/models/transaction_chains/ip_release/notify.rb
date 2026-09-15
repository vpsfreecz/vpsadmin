module TransactionChains
  module IpRelease
    class Notify < ::TransactionChain
      label 'IP release notice'
      allow_empty

      def link_chain(campaign, event, actor)
        raise ArgumentError, 'invalid notice event' unless %w[requested reminder].include?(event)

        campaign.notification_targets(event) do |request, addresses|
          owner = request.original_user
          log = mail(:"ip_release_#{event}", user: owner, vars: {
            user: owner, request: request, campaign: campaign, addresses: addresses,
            webui_url: ::SysConfig.get(:webui, :base_url).to_s.chomp('/')
          })
          next unless log

          request.ip_release_request_notices.create!(mail_log: log, event:, created_by: actor)
        end
      end
    end
  end
end
