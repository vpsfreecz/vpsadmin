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
        raise "cannot change attribute '#{attr}'" unless %w[addrs label is_universal location_id].include?(attr)

        db_changes[attr] = ns.send(attr)
      end

      # The nameserver was universal and now is assigned to a location OR the location
      # has changed.
      if (ns.is_universal_changed? && ns.location_id_changed? && !ns.is_universal) \
          || ns.location_id_changed?
        # Set another NS to all VPSes using this server and not
        # being in the new location.
        ::Vps.including_deleted.where(dns_resolver: ns).joins(:node)
             .where('location_id != ?', ns.location_id).each do |vps|
          lock(vps)

          new_ns = ::DnsResolver.pick_suitable_resolver_for_vps(vps, except: [ns.id])

          append(Transactions::Vps::DnsResolver, args: [vps, ns, new_ns]) do
            edit(vps, dns_resolver_id: new_ns.id)
          end

          changed_vpses << vps.id
        end
      end

      if ns.addrs_changed?
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
