module TransactionChains
  class Network::AddIps < ::TransactionChain
    label 'IP+'

    # @param network [Network]
    # @param n [Integer] number of IP addresses to add
    def link_chain(network, n)
      lock(network)
      ips = network.add_ips(n, lock: false)

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        ips.each { |ip| t.just_create(ip) }
      end
    end
  end
end
