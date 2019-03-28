module TransactionChains
  class Vps::SetUserNamespaceMap < ::TransactionChain
    label 'Set userns'

    def link_chain(vps, userns_map)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      selector = VpsAdmin::API::MountSelector.new(vps.dataset_in_pool)

      # Unmount all related mounts
      selector.each_vps_unmount do |vps, mounts|
        lock(vps)
        append(Transactions::Vps::Umount, args: [vps, mounts])
      end

      # Ensure appropriate osctl user is present
      use_chain(UserNamespaceMap::Use, args: [userns_map, vps.node])

      # Change UID/GID map
      append_t(Transactions::Vps::SetMap, args: [vps, userns_map]) do |t|
        t.edit(vps.dataset_in_pool, user_namespace_map_id: userns_map.id)
      end

      # Remount all mounts
      selector.each_vps_mount do |vps, mounts|
        append(Transactions::Vps::Mount, args: [vps, mounts])
      end

      # Original osctl user is no longer needed
      use_chain(UserNamespaceMap::Disuse, args: vps)
    end
  end
end
