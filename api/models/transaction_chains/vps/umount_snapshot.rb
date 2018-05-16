module TransactionChains
  # Umount local or remote snapshots.
  class Vps::UmountSnapshot < ::TransactionChain
    label 'Umount snapshot'

    def link_chain(vps, mount, regenerate = true)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      mount.confirmed = ::Mount.confirmed(:confirm_destroy)
      mount.save!

      remote = mount.snapshot_in_pool.dataset_in_pool.pool.node_id != vps.node_id

      use_chain(Vps::Mounts, args: vps) if regenerate
      # Umount must be done even if the VPS seems to be stopped,
      # because that's not certain information.
      use_chain(Vps::Umount, args: [vps, [mount]])

      append_t(
        Transactions::Storage::RemoveClone,
        args: [
          mount.snapshot_in_pool,
          vps.node.vpsadminos? ? vps.userns_map : nil,
        ]
      ) do |t|
        t.destroy(mount)
        t.decrement(mount.snapshot_in_pool, :reference_count)
        t.edit(mount.snapshot_in_pool, mount_id: nil)
        t.just_create(vps.log(:umount, {id: mount.id, dst: mount.dst})) unless included?
      end
    end
  end
end
