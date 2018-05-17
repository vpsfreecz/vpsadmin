module TransactionChains
  # Remove osctl user from node, unless it is still used by other VPS
  class UserNamespaceMap::Disuse < ::TransactionChain
    label 'Disuse userns'
    allow_empty

    def link_chain(vps)
      lock(vps.userns_map)

      userns_map_vpses = ::Vps.joins(:dataset_in_pool).where(
        dataset_in_pools: {user_namespace_map_id: vps.userns_map.id},
        node_id: vps.node_id,
      ).where.not(id: vps.id)

      return if userns_map_vpses.any?

      append_t(
        Transactions::UserNamespace::DestroyMap,
        args: [vps.node, vps.userns_map]
      ) do |t|
        uns_map_node = ::UserNamespaceMapNode.find_by!(
          user_namespace_map_id: vps.userns_map.id,
          node_id: vps.node_id,
        )

        t.just_destroy(uns_map_node)
      end
    end
  end
end
