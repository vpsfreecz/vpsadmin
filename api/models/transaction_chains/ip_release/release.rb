module TransactionChains
  module IpRelease
    class Release < ::TransactionChain
      label 'Release IPs'
      allow_empty

      def link_chain(campaign, attempt, actor)
        items = campaign.ip_release_request_addresses.order(:id).lock.to_a
        candidates = items.select do |item|
          item.ip_release_request.ip_release_campaign = campaign
          next false if item.released_at || item.excluded_at

          reason = item.exclusion_cause
          if reason
            item.exclude!(reason)
            next false
          end
          result = item.protection
          item.update!(last_attempt_at: attempt.created_at, last_result: result)
          result == 'eligible'
        end

        # User lifecycle reservations are shared across the entire attempt.
        owners = ::User.where(id: candidates.map(&:original_user_id)).order(:id).to_a
        owners.each { |owner| lock(owner) }
        owners.each { |owner| owner.reload(lock: true) }
        owners = owners.index_by(&:id)
        ips = ::IpAddress.where(id: candidates.map(&:ip_address_id)).order(:id).to_a
        ::IpAddress.lock_all_current!(self, ips)
        ips = ips.index_by(&:id)

        selected = candidates.select do |item|
          ip = ips[item.ip_address_id]
          owner = owners[item.original_user_id]
          reason = item.exclusion_cause(ip, owner)
          if reason
            item.exclude!(reason)
            next false
          end
          result = item.protection(ip, owner, lock: true)
          item.update!(last_result: result)
          result == 'eligible'
        end
        attempt.ip_release_attempt_addresses.where.not(ip_release_request_address_id: selected.map(&:id)).delete_all
        return if selected.empty?

        confirmation = use_chain(Ip::Disown, kwargs: { ips: selected.map { |item| ips.fetch(item.ip_address_id) }, defer: true })
        selected.each do |item|
          item.update!(release_chain: dst_chain || self, last_result: 'releasing')
          confirmation.edit(item, released_at: attempt.created_at, released_by_id: actor.id,
                                  active_ip_address_id: nil, last_result: 'released')
        end
        # Retained allocations stay owned, but this campaign no longer claims
        # them once the batch succeeds. Rollback leaves the campaign open.
        (items - selected).each do |item|
          confirmation.edit(item, active_ip_address_id: nil) if item.active_ip_address_id
        end
        confirmation.edit(campaign, closed_at: attempt.created_at, closed_by_id: actor.id)
      end
    end
  end
end
