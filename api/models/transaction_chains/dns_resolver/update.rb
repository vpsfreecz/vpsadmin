module TransactionChains
  class DnsResolver::Update < ::TransactionChain
    label 'Update'
    allow_empty

    VpsUpdate = Struct.new(:vps, :old_ns, :new_ns) do
      def vps_id
        vps.id
      end
    end

    def link_chain(ns, attrs)
      lock(ns)
      concerns(:affect, [ns.class.name, ns.id])

      old_ns = ::DnsResolver.find(ns.id)
      new_ns = ns

      new_ns.assign_attributes(attrs)
      raise ::ActiveRecord::RecordInvalid, new_ns unless new_ns.valid?

      db_changes = {}
      changed_vpses = []

      new_ns.changed.each do |attr|
        raise "cannot change attribute '#{attr}'" unless %w[addrs label is_universal location_id].include?(attr)

        db_changes[attr] = new_ns.send(attr)
      end

      # The nameserver was universal and now is assigned to a location OR the location
      # has changed.
      if (new_ns.is_universal_changed? && new_ns.location_id_changed? && !new_ns.is_universal) \
          || new_ns.location_id_changed?
        # Set another NS to all VPSes using this server and not
        # being in the new location.
        ::Vps
          .including_deleted
          .where(dns_resolver: new_ns)
          .joins(:node)
          .where('location_id != ?', new_ns.location_id)
          .each do |vps|
          lock(vps)
          concerns(:affect, [vps.class.name, vps.id])

          vps_update = VpsUpdate.new(
            vps,
            old_ns,
            ::DnsResolver.pick_suitable_resolver_for_vps(vps, except: [old_ns.id])
          )

          append(Transactions::Vps::DnsResolver, args: [vps, old_ns, vps_update.new_ns]) do
            edit(vps, dns_resolver_id: vps_update.new_ns.id)
          end

          changed_vpses << vps_update
        end
      end

      if new_ns.addrs_changed?
        # Only the address of the nameserver has changed.
        ::Vps
          .including_deleted
          .where(dns_resolver: old_ns)
          .where.not(vps_id: changed_vpses.map(&:vps_id))
          .each do |vps|
          lock(vps)
          concerns(:affect, [vps.class.name, vps.id])
          append(Transactions::Vps::DnsResolver, args: [vps, old_ns, new_ns])

          changed_vpses << VpsUpdate.new(vps, old_ns, new_ns)
        end
      end

      changed_vpses.each do |vps_update|
        mail(:vps_dns_resolver_change, {
          user: vps_update.vps.user,
          vars: {
            vps: vps_update.vps,
            old_dns_resolver: vps_update.old_ns,
            new_dns_resolver: vps_update.new_ns
          }
        })
      end

      if empty?
        new_ns.save!

      else
        append(Transactions::Utils::NoOp, args: find_node_id) do
          edit(new_ns, db_changes)
        end
      end

      new_ns
    end
  end
end
