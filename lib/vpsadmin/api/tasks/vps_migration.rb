module VpsAdmin::API::Tasks
  class VpsMigration < Base
    # Run VPS migration plans
    def run_plans
      ActiveRecord::Base.transaction { do_run_plans }
    end

    protected
    def do_run_plans
      ::MigrationPlan.where(
          state: [
              ::MigrationPlan.states[:running],
              ::MigrationPlan.states[:cancelling],
          ]
      ).each do |plan|
        puts "Plan ##{plan.id} #{plan.state}"
        run_plan(plan)
      end
    end

    def run_plan(plan)
      # Close finished migrations
      plan.vps_migrations.includes(
          :transaction_chain
      ).joins(
          :transaction_chain
      ).where(
          state: ::VpsMigration.states[:running],
      ).where.not(
          transaction_chains: {state: ::TransactionChain.states[:queued]}
      ).each do |m|
        # The migration has finished - successfully or not
        case m.transaction_chain.state.to_sym
        when :done
          puts "  Migration of VPS ##{m.vps_id} finished successfully"
          m.state = ::VpsMigration.states[:done]

        when :rollbacking, :failed, :fatal, :resolved
          puts "  Migration of VPS ##{m.vps_id} failed"
          m.state = ::VpsMigration.states[:error]

          if plan.stop_on_error
            puts "  Cancelling migration plan due to an error"
            plan.finish!(error)
          end

        else
          fail "unsupported transaction chain state '#{m.transaction_chain.state}'"
        end
        
        m.finished_at = Time.now
        m.save!
      end

      # Check if the plan is finished
      running = plan.vps_migrations.where(
          state: ::VpsMigration.states[:running],
      ).count

      if running <= 0
        queued = plan.vps_migrations.where(
            state: ::VpsMigration.states[:queued]
        ).count

        # No running migrations, nothing in the queue -> finished
        if queued == 0
          puts "  Migration plan is finished"
          plan.finish!(plan.state == 'running' ? :done : :cancelled)
          return
        end
      end

      return if plan.state == 'cancelling'

      # Start new migrations if any
      schedule_n = plan.concurrency - running
      
      if schedule_n <= 0
        puts "  #{running} migrations running, nothing to do"
        return
      end
      
      puts "  Start at most #{schedule_n} new migrations"

      locks = []
      plan.resource_locks.each { |l| locks << l }

      i = 0

      plan.vps_migrations.where(
          state: ::VpsMigration.states[:queued],
      ).order('created_at').each do |m|

        begin
          puts "   VPS ##{m.vps.id} from #{m.vps.node.domain_name} to #{m.dst_node.domain_name} "
          migrate_vps(m, locks)
          i += 1

          break if i >= schedule_n

        rescue ResourceLocked
          puts "      resource locked"
        end

      end
    end

    def migrate_vps(m, locks)
      chain = TransactionChains::Vps::Migrate.fire2(
          args: [m.vps, m.dst_node],
          locks: locks,
      )
     
      m.update!(
          state: ::VpsMigration.states[:running],
          started_at: Time.now,
          transaction_chain: chain,
      )
    end
  end
end
