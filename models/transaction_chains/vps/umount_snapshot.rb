module TransactionChains
  # Umount local or remote snapshots.
  class Vps::UmountSnapshot < ::TransactionChain
    label 'Umount snapshot'

    def link_chain(vps, mount)
      lock(vps)

      mount.confirmed = ::Mount.confirmed(:confirm_destroy)
      mount.save!

      use_chain(Vps::Mounts, args: vps)

      # Umount must be done even if the VPS seems to be stopped,
      # because that's not certain information.
      use_chain(Vps::Umount, args: [vps, [mount]])

      if mount.dataset_in_pool_id
        fail 'not implemented'

      elsif mount.snapshot_in_pool_id
        append(Transactions::Storage::RemoveClone, args: mount.snapshot_in_pool) do
          destroy(mount)
          decrement(mount.snapshot_in_pool, :reference_count)
          edit(mount.snapshot_in_pool, mount_id: nil)
        end

      else
        fail 'not implemented'
      end
    end
  end
end
