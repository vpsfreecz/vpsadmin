module TransactionChains
  class Cluster::GenerateKnownHosts < ::TransactionChain
    label 'Known hosts'

    def link_chain
      t = ::NodeCurrentStatus.table_name

      ::Node.joins(:node_current_status).where(
        "(#{t}.updated_at IS NULL AND UNIX_TIMESTAMP() - UNIX_TIMESTAMP(CONVERT_TZ(#{t}.created_at, 'UTC', 'Europe/Prague')) <= 120)
        OR
        (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(CONVERT_TZ(#{t}.updated_at, 'UTC', 'Europe/Prague')) <= 120)"
      ).where.not(
        role: ::Node.roles[:mailer],
      ).each do |n|
        append(Transactions::Node::GenerateKnownHosts, args: n)
      end
    end
  end
end
