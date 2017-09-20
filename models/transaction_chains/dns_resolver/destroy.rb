module TransactionChains
  class DnsResolver::Destroy < ::TransactionChain
    label 'Destroy'
    allow_empty

    def link_chain(ns)
      lock(ns)
      concerns(:affect, [ns.class.name, ns.id])

      ::Vps.including_deleted.where(dns_resolver: ns).each do |vps|
        lock(vps)

        new_ns = ::DnsResolver.pick_suitable_resolver_for_vps(vps, except: [ns.id])

        append(Transactions::Vps::DnsResolver, args: [vps, ns, new_ns]) do
          edit(vps, dns_resolver_id: new_ns.id)
        end
      end

      if empty?
        ns.destroy!

      else
        append(Transactions::Utils::NoOp, args: find_node_id) do
          just_destroy(ns)
        end
      end
    end
  end
end
