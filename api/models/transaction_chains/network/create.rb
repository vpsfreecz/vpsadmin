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

      tn = ::NodeCurrentStatus.table_name
      cutoff = 120.seconds.ago.utc

      ::Node.joins(:node_current_status).where(
        "#{tn}.updated_at >= :cutoff OR (#{tn}.updated_at IS NULL AND #{tn}.created_at >= :cutoff)",
        cutoff:
      ).where(role: ::Node.roles[:node]).each do |n|
        append(Transactions::Network::Register, args: [n, net])
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.just_create(net)
      end
    end
  end
end
