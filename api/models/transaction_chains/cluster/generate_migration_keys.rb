module TransactionChains
  class Cluster::GenerateMigrationKeys < ::TransactionChain
    label 'Migration keys'

    def link_chain
      active_pools.where(migration_public_key: nil).each do |pool|
        append(Transactions::Pool::GenerateSendKey, args: pool)
      end
    end

    protected
    def active_pools
      t = ::NodeCurrentStatus.table_name

      ::Pool.joins(node: :node_current_status).where(
        "(#{t}.updated_at IS NULL AND UNIX_TIMESTAMP() - UNIX_TIMESTAMP(CONVERT_TZ(#{t}.created_at, 'UTC', 'Europe/Prague')) <= 120)
        OR
        (UNIX_TIMESTAMP() - UNIX_TIMESTAMP(CONVERT_TZ(#{t}.updated_at, 'UTC', 'Europe/Prague')) <= 120)"
      ).where(
        nodes: {
          role: ::Node.roles[:node],
          hypervisor_type: ::Node.hypervisor_types[:vpsadminos],
          active: true,
        },
      )
    end
  end
end
