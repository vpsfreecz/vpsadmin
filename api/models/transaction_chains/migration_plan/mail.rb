module TransactionChains
  class MigrationPlan::Mail < ::TransactionChain
    label 'Mail'
    allow_empty

    def link_chain(plan)
      concerns(:affect, [plan.class.name, plan.id])

      plan.vps_migrations.includes(:src_node, :dst_node, vps: [:user]).each do |m|
        next unless m.vps.user.mailer_enabled

        mail(:vps_migration_planned, {
               user: m.vps.user,
               vars: {
                 m: m,
                 vps: m.vps,
                 src_node: m.src_node,
                 dst_node: m.dst_node
               }
             })
      end
    end
  end
end
