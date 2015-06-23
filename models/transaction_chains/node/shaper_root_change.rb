module TransactionChains
  class Node::ShaperRootChange < ::TransactionChain
    label 'Sshaper*'

    def link_chain(node)
      lock(node)

      append(Transactions::Vps::ShaperRootChange, args: [node]) do
        edit_before(node, max_tx: node.max_tx_was, max_rx: node.max_rx_was)
      end
    end
  end
end
