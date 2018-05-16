module TransactionChains
  # Create osctl user on node, unless it already exists
  class UserNamespaceMap::Use < ::TransactionChain
    label 'Use userns'
    allow_empty

    def link_chain(userns_map, node)
      lock(userns_map)

      return if userns_map.nodes.where(id: node.id).any?

      append_t(Transactions::UserNamespace::CreateMap, args: [node, userns_map]) do |t|
        unsmap_on_node = ::UserNamespaceMapNode.create!(
          user_namespace_map: userns_map,
          node: node,
        )

        t.just_create(unsmap_on_node)
      end
    end
  end
end
