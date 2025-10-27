module TransactionChains
  class Vps::SoftDelete < ::TransactionChain
    label 'Soft delete'

    def link_chain(vps, target, _state, _log)
      if vps.container?
        lock(vps.dataset_in_pool)
      else
        lock(vps.storage_volume)
      end

      lock(vps)

      concerns(:affect, [vps.class.name, vps.id])

      # Stop VPS - should be already stopped when suspended (blocked)
      use_chain(TransactionChains::Vps::Stop, args: vps, kwargs: { rollback_stop: false })

      # Remove IP addresses
      if target
        vps.network_interfaces.each do |netif|
          use_chain(NetworkInterface::Clear, args: netif)
        end
      end

      append_t(Transactions::Utils::NoOp, args: vps.node_id) do |t|
        # Mark all resources as disabled until they are really freed by
        # hard_delete. Revive should mark them back as enabled.
        objs = [vps]

        if vps.container?
          objs << vps.dataset_in_pool
          objs.concat(vps.dataset_in_pool.subdatasets_in_pool)
        else
          objs << vps.storage_volume
        end

        objs.each do |obj|
          lock(obj)

          ::ClusterResourceUse.for_obj(obj).each do |use|
            lock(use.user_cluster_resource)
            t.edit(use, enabled: 0)
          end
        end
      end
    end
  end
end
