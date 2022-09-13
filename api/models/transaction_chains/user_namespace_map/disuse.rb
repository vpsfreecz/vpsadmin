module TransactionChains
  # Remove osctl user from node, unless it is still used by other VPS
  class UserNamespaceMap::Disuse < ::TransactionChain
    label 'Disuse userns'
    allow_empty

    def link_chain(vps, userns_map: nil, pool: nil)
      userns_map ||= vps.userns_map
      pool ||= vps.pool

      lock(userns_map)

      userns_map_vpses = ::Vps.joins(:dataset_in_pool).where(
        dataset_in_pools: {
          user_namespace_map_id: userns_map.id,
          pool_id: pool.id,
        },
      ).where.not(id: vps.id)

      return if userns_map_vpses.any?

      append_t(
        Transactions::UserNamespace::DestroyMap,
        args: [pool, userns_map]
      ) do |t|
        uns_map_pool = ::UserNamespaceMapPool.find_by!(
          user_namespace_map_id: userns_map.id,
          pool_id: pool.id,
        )

        t.just_destroy(uns_map_pool)
      end
    end
  end
end
