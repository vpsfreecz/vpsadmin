module TransactionChains
  # Remove osctl user from node, unless it is still used by other VPS
  class UserNamespace::Disuse < ::TransactionChain
    label 'Disuse userns'
    allow_empty

    def link_chain(vps)
      userns_vpses = ::Vps.joins(:dataset_in_pool).where(
          dataset_in_pools: {user_namespace_id: vps.userns.id},
          node_id: vps.node_id,
      ).where.not(id: vps.id)

      return if userns_vpses.any?

      append_t(
        Transactions::UserNamespace::Destroy,
        args: [vps.node, vps.userns]
      ) do |t|
        uns_node = ::UserNamespaceNode.find_by!(
            user_namespace_id: vps.userns.id,
            node_id: vps.node_id,
        )

        t.just_destroy(uns_node)
      end
    end
  end
end
