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
      user.datasets.where(expiration: nil).order('full_name DESC').each do |ds|
        dip = ds.primary_dataset_in_pool!
        next if dip.pool.role == 'hypervisor'  # VPS datasets are already deleted
        use_chain(DatasetInPool::Destroy, args: [dip, true])
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
