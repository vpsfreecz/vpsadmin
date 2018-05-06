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

      use_chain(Vps::DelIp, args: [
        vps,
        vps.ip_addresses.joins(:network).where(
          networks: {role: [
            ::Network.roles[:public_access],
            ::Network.roles[:private_access],
          ]}
        )
      ])

      append(Transactions::Utils::NoOp, args: vps.node_id) do
        # Mark all resources as disabled until they are really freed by
        # hard_delete. Revive should mark them back as enabled.
        objs = [vps, vps.dataset_in_pool]
        objs.concat(vps.dataset_in_pool.subdatasets_in_pool)

        objs.each do |obj|
          chain.lock(obj)

          ::ClusterResourceUse.for_obj(obj).each do |use|
            chain.lock(use.user_cluster_resource)
            edit(use, enabled: 0)
          end
        end
      end
    end
  end
end
