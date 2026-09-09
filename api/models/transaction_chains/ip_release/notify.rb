module TransactionChains
  module IpRelease
    class Notify < ::TransactionChain
      label 'IP release notice'
      allow_empty

      def link_chain(campaign, event, actor)
        raise ArgumentError, 'invalid notice event' unless %w[requested reminder].include?(event)

        campaign.ip_release_requests.includes(:user).order(:id).each do |request|
          initially_notified = request.ip_release_request_notices.where(event: 'requested').exists?
          next if (event == 'requested' && initially_notified) || (event == 'reminder' && !initially_notified)

          owner = request.original_user
          next unless request.user_available?(owner) && owner.mailer_enabled

          addresses = request.ip_release_request_addresses.order(:id).select { |item| item.protection == 'eligible' }
          next if addresses.empty?

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
