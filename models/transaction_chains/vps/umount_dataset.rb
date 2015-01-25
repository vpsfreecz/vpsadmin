module TransactionChains
  # Umount local or remote datasets.
  class Vps::UmountDataset < ::TransactionChain
    label 'Umount dataset'

    def link_chain(vps, mount)
      lock(vps)

      mount.confirmed = ::Mount.confirmed(:confirm_destroy)
      mount.save!

      use_chain(Vps::Mounts, args: vps)
      # Umount must be done even if the VPS seems to be stopped,
      # because that's not certain information.
      use_chain(Vps::Umount, args: [vps, [mount]])

      append(Transactions::Utils::NoOp, args: vps.vps_server) do
        destroy(mount)
      end
    end
  end
end
