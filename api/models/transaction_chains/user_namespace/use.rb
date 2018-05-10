module TransactionChains
  # Create osctl user on node, unless it already exists
  class UserNamespace::Use < ::TransactionChain
    label 'Use userns'
    allow_empty

    def link_chain(userns, node)
      lock(userns)

      return if userns.nodes.where(id: node.id).any?

      append_t(Transactions::UserNamespace::Create, args: [node, userns]) do |t|
        uns_on_node = ::UserNamespaceNode.create!(
          user_namespace: userns,
          node: node,
        )

        t.just_create(uns_on_node)
      end
    end
  end
end
