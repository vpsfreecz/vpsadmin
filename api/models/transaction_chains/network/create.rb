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

      ::Node.joins(:node_current_status).where(
        "(#{tn}.updated_at IS NULL AND UNIX_TIMESTAMP() - UNIX_TIMESTAMP(CONVERT_TZ(#{tn}.created_at, 'UTC', 'Europe/Prague')) <= 120)
        OR
        (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(CONVERT_TZ(#{tn}.updated_at, 'UTC', 'Europe/Prague')) <= 120)"
      ).where(role: ::Node.roles[:node]).each do |n|
        append(Transactions::Network::Register, args: [n, net])
      end

      append_t(Transactions::Utils::NoOp, args: find_node_id) do |t|
        t.just_create(net)
      end
    end
  end
end
