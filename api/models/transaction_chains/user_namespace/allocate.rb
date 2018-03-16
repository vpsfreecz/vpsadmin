module TransactionChains
  class UserNamespace::Allocate < ::TransactionChain
    label 'Allocate userns'

    def link_chain(user, node = nil)
      block = ::UserNamespaceBlock.where(user_namespace_id: nil).order('`index`').take!
      ugid = ::UserNamespaceUgid.where(user_namespace_id: nil).order('ugid').take!
      uns = ::UserNamespace.create!(
          user: user,
          user_namespace_ugid: ugid,
          block_count: 1,
          offset: block.offset,
          size: block.size
      )
      block.update!(user_namespace: uns)
      ugid.update!(user_namespace: uns)

      confirmations = Proc.new do |t|
        t.just_create(uns)
        t.edit_before(block, user_namespace_id: nil)
        t.edit_before(ugid, user_namespace_id: nil)
      end

      if node
        append_t(Transactions::UserNamespace::Create, args: [node, uns], &confirmations)

      else
        append_t(Transactions::Utils::NoOp, args: find_node_id, &confirmations)
      end

      uns
    end
  end
end
