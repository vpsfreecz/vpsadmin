module TransactionChains
  class UserNamespace::Free < ::TransactionChain
    label 'Free userns'

    def link_chain(userns, node = nil)
      lock(userns)

      userns.user_namespace_blocks.each do |blk|
        lock(blk)
      end

      confirmations = Proc.new do |t|
        t.edit(userns.user_namespace_ugid, user_namespace_id: nil)

        userns.user_namespace_blocks.each do |block|
          t.edit(block, user_namespace_id: nil)
        end

        t.just_destroy(userns)
      end

      if node
        append_t(Transactions::UserNamespace::Destroy, args: [node, userns], &confirmations)

      else
        append_t(Transactions::Utils::NoOp, args: find_node_id, &confirmations)
      end
    end
  end
end
