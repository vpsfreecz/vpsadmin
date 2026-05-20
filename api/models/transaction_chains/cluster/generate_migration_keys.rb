module TransactionChains
  class Cluster::GenerateMigrationKeys < ::TransactionChain
    label 'Migration keys'

    def link_chain
      active_pools.group_by { |pool| [pool.node_id, pool.name] }.each_value do |pools|
        public_keys = pools.map(&:migration_public_key).compact.uniq
        next if public_keys.one? && pools.none? { |pool| pool.migration_public_key.nil? }

        append(
          Transactions::Pool::GenerateSendKey,
          args: pools.first,
          kwargs: { pool_ids: pools.map(&:id) }
        )
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
