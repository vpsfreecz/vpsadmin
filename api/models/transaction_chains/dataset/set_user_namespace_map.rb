module TransactionChains
  class Dataset::SetUserNamespaceMap < ::TransactionChain
    label 'Set userns'

    def link_chain(dip, userns_map)
      lock(dip)
      concerns(:affect, [dip.dataset.class.name, dip.dataset.id])

      # TODO: unmount all mounts of this datasets... and probably all
      #       subdatasets as well
      #       we also have to handle situation where we need to unmount e.g.
      #       `/mnt/something`, but some other dataset/snapshot might be mounted
      #       below that point, e.g. `/mnt/something/whatever`. So we need to
      #       unmount all of that in the correct order.

      append_t(Transactions::Storage::SetMap, args: [dip, userns_map]) do |t|
        t.edit(dip, user_namespace_map_id: userns_map && userns_map.id)
      end

      # TODO: remount all mounts
    end
  end
end
