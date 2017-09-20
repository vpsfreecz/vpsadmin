module TransactionChains
  class Vps::Revive < ::TransactionChain
    label 'Revive'

    def link_chain(vps, target, state, log)
      lock(vps.dataset_in_pool)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])
      
      chain = self
      
      append(Transactions::Utils::NoOp, args: vps.node_id) do
        # Mark all resources as confirmed
        objs = [vps, vps.dataset_in_pool]
        objs.concat(vps.dataset_in_pool.subdatasets_in_pool)

        objs.each do |obj|
          chain.lock(obj)

          ::ClusterResourceUse.for_obj(obj).each do |use|
            chain.lock(use.user_cluster_resource)

            use.update!(enabled: true)
            raise VpsAdmin::API::Exceptions::ClusterResourceAllocationError, use unless use.valid?

            edit_before(use, enabled: 0)
          end
        end
      end

      use_chain(TransactionChains::Vps::Start, args: vps)
    end
  end
end
