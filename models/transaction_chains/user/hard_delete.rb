module TransactionChains
  class User::HardDelete < ::TransactionChain
    label 'Hard delete user'

    def link_chain(user, target, state, log)
      # Destroy all VPSes
      user.vpses.where(object_state: [
          ::Vps.object_states[:active],
          ::Vps.object_states[:suspended],
          ::Vps.object_states[:soft_delete],
      ]).each do |vps|
        vps.set_object_state(:hard_delete, reason: 'User was hard deleted',
                             chain: self)
      end

      # Destroy all datasets
      user.datasets.all.order('full_name DESC').each do |ds|
        begin
          dip = ds.primary_dataset_in_pool!

          if dip.pool.role == 'hypervisor'
            # VPS datasets are already deleted but from hypervisor pools only,
            # we have to take care about backups.
            ds.dataset_in_pools.joins(:pool).where(
                pools: {role: ::Pool.roles[:backup]}
            ).each do |backup|
              use_chain(DatasetInPool::Destroy, args: [backup, true])
            end
            
          else # primary pool, delete right away with all backups
            ds.set_object_state(:deleted, chain: self)
          end

        rescue ActiveRecord::RecordNotFound
          # The dataset is not present on any primary/hypervisor pool as it has
          # been already deleted and exists only in backup.
          
          ds.set_object_state(:deleted, chain: self)
        end
      end

      # Destroy snapshot downloads
      user.snapshot_downloads.each do |dl|
        use_chain(Dataset::RemoveDownload, args: dl)
      end

      append(Transactions::Utils::NoOp, args: find_node_id) do
        # Free all IP addresses
        ::IpAddress.where(user: user).each do |ip|
          edit(ip, user_id: nil)
        end
      end
    end
  end
end
