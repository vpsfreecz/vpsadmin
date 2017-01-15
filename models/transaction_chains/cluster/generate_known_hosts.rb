module TransactionChains
  class Cluster::GenerateKnownHosts < ::TransactionChain
    label 'Known hosts'

    def link_chain
      ::Node.where.not(role: 'mailer').each do |n|
        append(Transactions::Node::GenerateKnownHosts, args: n)
      end
    end
  end
end
