module TransactionChains
  module SecurityAdvisories
    class Mail < ::TransactionChain
      label 'Security advisory notifications'
      allow_empty

      EVENT_TYPES = {
        announce: 'security_advisory.announced',
        update: 'security_advisory.updated'
      }.freeze

      def link_chain(advisory, action, update = nil)
        concerns(:affect, [advisory.class.name, advisory.id])

        advisory.security_advisory_users.includes(:user).joins(:user).where(
          users: {
            object_state: [
              ::User.object_states[:active],
              ::User.object_states[:suspended]
            ]
          }
        ).order(:user_id).each do |row|
          route_advisory_event!(advisory, row.user, action, update)
        end

        advisory
      end

      protected

      def route_advisory_event!(advisory, user, action, update)
        action = action.to_sym
        affected_vpses = advisory.security_advisory_vpses
                                 .includes(:vps, :node)
                                 .where(user:)
                                 .order(:vps_id)

        route_event!(
          EVENT_TYPES.fetch(action),
          user:,
          source: update || advisory,
          subject: event_subject(advisory, action),
          summary: event_summary(update || advisory),
          parameters: event_parameters(advisory, affected_vpses, update)
        )
      end

      def event_subject(advisory, action)
        verb = action == :update ? 'updated' : 'announced'
        title = advisory.name.present? ? " - #{advisory.name}" : ''

        "Security advisory ##{advisory.id} #{verb}#{title}"[0, 255]
      end

      def event_parameters(advisory, affected_vpses, update)
        ret = {
          advisory_id: advisory.id,
          advisory_name: advisory.name,
          cves: advisory.cve_ids,
          state: advisory.state,
          published_at: advisory.published_at&.iso8601,
          affected_vps_count: affected_vpses.count,
          affected_vpses: affected_vps_sample(affected_vpses)
        }

        if update
          ret[:update_id] = update.id
          ret[:update_summary] = truncate_value(translated_value(update, :summary), 1_000)
        end

        ret
      end

      def event_summary(object)
        truncate_value(translated_value(object, :summary), ::Event::MAX_SUMMARY_LENGTH)
      end

      def affected_vps_sample(affected_vpses)
        affected_vpses.limit(
          VpsAdmin::API::Events::PARAMETER_SAMPLE_LIMIT
        ).map do |row|
          {
            vps_id: row.vps_id,
            vps_hostname: row.vps.hostname,
            node_id: row.node_id,
            node_domain_name: row.node.domain_name,
            vulnerable_until: row.vulnerable_until&.iso8601,
            mitigated_since: row.mitigated_since&.iso8601
          }
        end
      end

      def translated_value(object, attr)
        return if object.nil?

        ::Language.order(:id).each do |language|
          method = :"#{language.code}_#{attr}"
          next unless object.respond_to?(method)

          value = object.public_send(method)
          return value.to_s if value.present?
        end

        object.public_send(attr).to_s if object.respond_to?(attr)
      end

      def truncate_value(value, limit)
        return if value.blank?

        value.to_s[0, limit]
      end

      def webui_url
        (::SysConfig.get(:webui, :base_url) || '').chomp('/')
      rescue StandardError
        ''
      end
    end
  end
end
