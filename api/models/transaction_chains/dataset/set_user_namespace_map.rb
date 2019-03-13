module TransactionChains
  class Dataset::SetUserNamespaceMap < ::TransactionChain
    label 'Set userns'

    def link_chain(dip, userns_map)
      lock(dip)
      concerns(:affect, [dip.dataset.class.name, dip.dataset.id])

      selector = VpsAdmin::API::MountSelector.new(dip)

      # Unmount all related mounts
      selector.each_vps_unmount do |vps, mounts|
        lock(vps)
        append(Transactions::Vps::Umount, args: [vps, mounts])
      end

      # Change UID/GID map
      append_t(Transactions::Storage::SetMap, args: [dip, userns_map]) do |t|
        t.edit(dip, user_namespace_map_id: userns_map && userns_map.id)
      end

      # Remount all mounts
      selector.each_vps_mount do |vps, mounts|
        append(Transactions::Vps::Mount, args: [vps, mounts])
      end
    end
  end
end
