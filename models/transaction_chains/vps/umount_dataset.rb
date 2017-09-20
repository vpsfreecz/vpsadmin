module TransactionChains
  # Umount local or remote datasets.
  class Vps::UmountDataset < ::TransactionChain
    label 'Umount dataset'

    def link_chain(vps, mount, regenerate = true)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      mount.confirmed = ::Mount.confirmed(:confirm_destroy)
      mount.save!

      use_chain(Vps::Mounts, args: vps) if regenerate
      # Umount must be done even if the VPS seems to be stopped,
      # because that's not certain information.
      use_chain(Vps::Umount, args: [vps, [mount]])

      append_t(Transactions::Utils::NoOp, args: vps.node_id) do |t|
        t.destroy(mount)

        t.just_create(vps.log(:umount, {id: mount.id, dst: mount.dst})) unless included?
      end
    end
  end
end
