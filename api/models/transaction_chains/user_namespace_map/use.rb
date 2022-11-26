module TransactionChains
  # Create osctl user on node, unless it already exists
  class UserNamespaceMap::Use < ::TransactionChain
    label 'Use userns'
    allow_empty

    def link_chain(vps, userns_map)
      append_t(Transactions::UserNamespace::UseMap, args: [vps, userns_map])
    end
  end
end
