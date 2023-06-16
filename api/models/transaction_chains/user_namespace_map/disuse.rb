module TransactionChains
  # Remove osctl user from node, unless it is still used by other VPS
  class UserNamespaceMap::Disuse < ::TransactionChain
    label 'Disuse userns'
    allow_empty

    def link_chain(vps, userns_map: nil)
      userns_map ||= vps.user_namespace_map
      append_t(Transactions::UserNamespace::DisuseMap, args: [vps, userns_map])
    end
  end
end
