module TransactionChains
  class Vps::SoftDelete < ::TransactionChain
    label 'Soft delete'

    def link_chain(vps, target, state, log)
      lock(vps.dataset_in_pool)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      # Stop VPS - should be already stopped when suspended (blocked)
      use_chain(TransactionChains::Vps::Stop, args: vps)

      chain = self

      # Free IP addresses only if this is the target state, because hard_delete
      # (Vps::Destroy) will free all resources anyway.
      if target
        ips = [
            vps.free_resource!(:ipv4, chain: self),
            vps.free_resource!(:ipv6, chain: self)
        ].compact
      end
      
      append(Transactions::Utils::NoOp, args: vps.vps_server) do
        # Free IP addresses
        ips.each { |ip| destroy(ip) } if target

        # Mark all resources as confirm_destroy to 'free' them, until
        # they are really freed by hard_delete.
        # Revive should mark them back as confirmed.
        objs = [vps, vps.dataset_in_pool]
        objs.concat(vps.dataset_in_pool.subdatasets_in_pool)

        objs.each do |obj|
          chain.lock(obj)

          ::ClusterResourceUse.for_obj(obj).each do |use|
            chain.lock(use.user_cluster_resource)
            edit(use, confirmed: ::ClusterResourceUse.confirmed(:confirm_destroy))
          end
        end
      end
    end
  end
end
