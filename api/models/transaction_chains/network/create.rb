module TransactionChains
  class Network::Create < ::TransactionChain
    label 'Create'

    # @param net [Network]
    # @param opts [Hash]
    # @option opts [Boolean] add_ips
    def link_chain(net, opts)
      net.save!
      lock(net)

      use_chain(Network::AddIps, args: [net, net.size]) if opts[:add_ips]

      if net.role != 'interconnecting'
        ::Node.where(role: 'node').each do |n|
          append(Transactions::Network::Register, args: [n, net])
        end
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.just_create(net)
      end
    end
  end
end
