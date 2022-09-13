module TransactionChains
  # Create osctl user on node, unless it already exists
  class UserNamespaceMap::Use < ::TransactionChain
    label 'Use userns'
    allow_empty

    def link_chain(userns_map, pool)
      lock(userns_map)

      return if userns_map.pools.where(id: pool.id).any?

      append_t(Transactions::UserNamespace::CreateMap, args: [pool, userns_map]) do |t|
        unsmap_on_pool = ::UserNamespaceMapPool.create!(
          user_namespace_map: userns_map,
          pool: pool,
        )

        t.just_create(unsmap_on_pool)
      end
    end
  end
end
