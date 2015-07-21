module TransactionChains
  class DnsResolver::Update < ::TransactionChain
    label 'Update'
    allow_empty

    def link_chain(ns, attrs)
      lock(ns)
      concerns(:affect, [ns.class.name, ns.id])

      ns.assign_attributes(attrs)
      raise ::ActiveRecord::RecordInvalid, ns unless ns.valid?

      db_changes = {}
      changed_vpses = []

      ns.changed.each do |attr|
        unless %w(dns_ip dns_label dns_is_universal dns_location).include?(attr)
          fail "cannot change attribute '#{attr}'"
        end

        db_changes[attr] = ns.send(attr)
      end

      # The nameserver was universal and now is assigned to a location OR the location
      # has changed.
      if (ns.dns_is_universal_changed? && ns.dns_location_changed? && !ns.dns_is_universal) \
          || ns.dns_location_changed?
        # Set another NS to all VPSes using this server and not
        # being in the new location.
        ::Vps.including_deleted.where(dns_resolver: ns).joins(:node)
            .where('server_location != ?', ns.dns_location).each do |vps|
          lock(vps)

          new_ns = ::DnsResolver.pick_suitable_resolver_for_vps(vps, except: [ns.id])

          append(Transactions::Vps::DnsResolver, args: [vps, ns, new_ns]) do
            edit(vps, dns_resolver_id: new_ns.id)
          end

          changed_vpses << vps.id
        end
      end

      if ns.dns_ip_changed?
        # Only the address of the nameserver has changed.
        old_ns = ::DnsResolver.find(ns.id)

        ::Vps.including_deleted.where(dns_resolver: ns)
            .where.not(vps_id: changed_vpses).each do |vps|
          lock(vps)
          append(Transactions::Vps::DnsResolver, args: [vps, old_ns, ns])
        end
      end

      if empty?
        ns.save!

      else
        append(Transactions::Utils::NoOp, args: find_node_id) do
          edit(ns, db_changes)
        end
      end
    end
  end
end
