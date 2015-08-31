module TransactionChains
  class Cluster::GenerateKnownHosts < ::TransactionChain
    label 'Known hosts'

    def link_chain
      ::Node.where.not(server_type: 'mailer').each do |n|
        append(Transactions::Node::GenerateKnownHosts, args: n)
      end
    end
  end
end
