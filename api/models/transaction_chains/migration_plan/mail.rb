module TransactionChains
  class MigrationPlan::Mail < ::TransactionChain
    label 'Migration notifications'
    allow_empty

    def link_chain(plan)
      concerns(:affect, [plan.class.name, plan.id])

      plan.vps_migrations.includes(:src_node, :dst_node, vps: [:user]).each do |m|
        route_event!(
          'vps.migration_planned',
          user: m.vps.user,
          vps: m.vps,
          source: m,
          subject: "VPS ##{m.vps.id} migration planned",
          summary: "#{m.src_node.domain_name} -> #{m.dst_node.domain_name}",
          parameters: {
            migration_id: m.id,
            vps_id: m.vps.id,
            vps_hostname: m.vps.hostname,
            src_node_id: m.src_node.id,
            src_node_domain_name: m.src_node.domain_name,
            dst_node_id: m.dst_node.id,
            dst_node_domain_name: m.dst_node.domain_name,
            maintenance_window: m.maintenance_window
          }
        )
      end
    end
  end
end
