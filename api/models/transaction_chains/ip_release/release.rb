module TransactionChains
  module IpRelease
    class Release < ::TransactionChain
      label 'Release IP'
      allow_empty

      def link_chain(item, actor)
        owner = item.ip_release_request.original_user
        unless owner
          item.exclude!('owner_deleted')
          return
        end

        # User state transitions take this resource lock too. Retain it until
        # cleanup confirms so account deletion cannot free the same resources.
        lock(owner)
        owner.reload(lock: true)
        ip = ::IpAddress.find_by(id: item.ip_address_id)
        if ip
          lock(ip)
          ip.reload(lock: true)
        end
        reason = item.exclusion_cause(ip, owner)
        if reason
          item.exclude!(reason)
          return
        end

        result = item.protection(ip, owner, lock: true)
        if result == 'eligible'
          confirmation = use_chain(Ip::Update, args: [ip, { user: nil, environment: nil }])
          released = { released_at: Time.now, released_by_id: actor.id,
                       active_ip_address_id: nil, last_result: 'released', last_error: nil }
          if confirmation
            confirmation.edit(item, released)
            result = 'releasing'
          else
            item.assign_attributes(released)
            result = 'released'
          end
        end
        item.update!(last_attempt_at: Time.now, last_result: result, last_error: nil)
      end
    end
  end
end
