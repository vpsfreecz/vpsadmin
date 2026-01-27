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

      recent = 120.seconds.ago

      ::Pool.joins(node: :node_current_status).where(
        "(#{t}.updated_at IS NULL AND #{t}.created_at >= :recent)
        OR
        (#{t}.updated_at >= :recent)",
        recent: recent
      ).where(
        nodes: {
          role: ::Node.roles[:node],
          hypervisor_type: ::Node.hypervisor_types[:vpsadminos],
          active: true
        }
      )
    end
  end
end
