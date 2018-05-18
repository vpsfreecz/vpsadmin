module TransactionChains
  class Vps::SetUserNamespaceMap < ::TransactionChain
    label 'Set userns'

    def link_chain(vps, userns_map)
      lock(vps)
      concerns(:affect, [vps.class.name, vps.id])

      # TODO: unmount all mounts of this dataset... and probably all
      #       subdatasets as well
      #       we also have to handle situation where we need to unmount e.g.
      #       `/mnt/something`, but some other dataset/snapshot might be mounted
      #       below that point, e.g. `/mnt/something/whatever`. So we need to
      #       unmount all of that in the correct order.

      use_chain(UserNamespaceMap::Use, args: [userns_map, vps.node])

      append_t(Transactions::Vps::SetMap, args: [vps, userns_map]) do |t|
        t.edit(vps.dataset_in_pool, user_namespace_map_id: userns_map.id)
      end

      use_chain(UserNamespaceMap::Disuse, args: vps)

      # TODO: remount all mounts
    end
  end
end
