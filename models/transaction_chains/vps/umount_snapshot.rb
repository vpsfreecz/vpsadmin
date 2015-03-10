module TransactionChains
  # Umount local or remote snapshots.
  class Vps::UmountSnapshot < ::TransactionChain
    label 'Umount snapshot'

    def link_chain(vps, mount)
      lock(vps)
      set_concerns(:affect, [vps.class.name, vps.id])

      mount.confirmed = ::Mount.confirmed(:confirm_destroy)
      mount.save!

      remote = mount.snapshot_in_pool.dataset_in_pool.pool.node_id != vps.vps_server

      use_chain(Vps::Mounts, args: vps)
      # Umount must be done even if the VPS seems to be stopped,
      # because that's not certain information.
      use_chain(Vps::Umount, args: [vps, [mount]])

      cleanup = Proc.new do
        destroy(mount)
        decrement(mount.snapshot_in_pool, :reference_count)
        edit(mount.snapshot_in_pool, mount_id: nil)
      end

      if remote
        append(Transactions::Storage::RemoveClone, args: mount.snapshot_in_pool, &cleanup)

      else
        append(Transactions::Utils::NoOp, args: vps.vps_server, &cleanup)
      end
    end
  end
end
