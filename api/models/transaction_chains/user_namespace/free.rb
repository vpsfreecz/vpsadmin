module TransactionChains
  class UserNamespace::Free < ::TransactionChain
    label 'Free userns'

    def link_chain(userns)
      lock(userns)

      userns.user_namespace_blocks.each do |blk|
        lock(blk)
      end

      confirmations = proc do |t|
        userns.user_namespace_maps.each do |map|
          t.just_destroy(map)
        end

        userns.user_namespace_blocks.each do |block|
          t.edit(block, user_namespace_id: nil)
        end

        t.just_destroy(userns)
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id, &confirmations)
    end
  end
end
