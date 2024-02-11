module TransactionChains
  class Mail::DailyReport < ::TransactionChain
    label 'Daily report'
    allow_empty

    has_hook :send,
             desc: 'Called when daily report is being sent',
             context: 'TransactionChains::Mail::DailyReport instance',
             args: {
               from: 'Starting time of this report'
             }

    def link_chain(lang)
      now = Time.now.utc

      mail(:daily_report, {
             language: lang,
             vars: call_hooks_for(
               :send,
               self,
               args: [now - (24 * 60 * 60), now],
               initial: vars(now)
             )
           })
    end

    protected

    def vars(now)
      t = now.strftime('%Y-%m-%d %H:%M:%S')

      chains = ::TransactionChain.where(
        'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
      )
      trans = ::Transaction.where(
        'DATE_ADD(created_at, INTERVAL 1 DAY) > ?', t
      )

      {
        date: {
          start: (now - (24 * 60 * 60)),
          end: now
        },

        users: {
          new: {
            changed: ::User.existing.where(
              'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
            ).order('id')
          },

          active: {
            all: ::User.unscoped.where(object_state: ::User.object_states[:active]),
            changed: ::User.unscoped.where(
              object_state: ::User.object_states[:active]
            ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND users.id = s.row_id")
                           .where('s.state = ?', ::User.object_states[:active])
                           .where('s.created_at != users.created_at')
                           .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                           .order('users.id')
          },

          soft_deleted: {
            all: ::User.unscoped.where(object_state: ::User.object_states[:soft_delete]),
            changed: ::User.unscoped.where(
              object_state: ::User.object_states[:soft_delete]
            ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND users.id = s.row_id")
                           .where('s.state = ?', ::User.object_states[:soft_delete])
                           .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                           .order('users.id')
          },

          hard_deleted: {
            all: ::User.unscoped.where(object_state: ::User.object_states[:hard_delete]),
            changed: ::User.unscoped.where(
              object_state: ::User.object_states[:hard_delete]
            ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND users.id = s.row_id")
                           .where('s.state = ?', ::User.object_states[:hard_delete])
                           .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                           .order('users.id')
          },

          suspended: {
            all: ::User.unscoped.where(object_state: ::User.object_states[:suspended]),
            changed: ::User.unscoped.where(
              object_state: ::User.object_states[:suspended]
            ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND users.id = s.row_id")
                           .where('s.state = ?', ::User.object_states[:suspended])
                           .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                           .order('users.id')
          }
        },

        vps: {
          new: {
            changed: ::Vps.existing.where(
              'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
            ).order('user_id')
          },

          active: {
            all: ::Vps.unscoped.where(object_state: ::Vps.object_states[:active]),
            changed: ::Vps.unscoped.where(
              object_state: ::Vps.object_states[:active]
            ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vpses.id = s.row_id")
                          .where('s.state = ?', ::Vps.object_states[:active])
                          .where('s.created_at != vpses.created_at')
                          .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                          .order('vpses.id')
          },

          soft_deleted: {
            all: ::Vps.unscoped.where(object_state: ::Vps.object_states[:soft_delete]),
            changed: ::Vps.unscoped.where(
              object_state: ::Vps.object_states[:soft_delete]
            ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vpses.id = s.row_id")
                          .where('s.state = ?', ::Vps.object_states[:soft_delete])
                          .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                          .order('vpses.id')
          },

          hard_deleted: {
            all: ::Vps.unscoped.where(object_state: ::Vps.object_states[:hard_delete]),
            changed: ::Vps.unscoped.where(
              object_state: ::Vps.object_states[:hard_delete]
            ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vpses.id = s.row_id")
                          .where('s.state = ?', ::Vps.object_states[:hard_delete])
                          .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                          .order('vpses.id')
          },

          suspended: {
            all: ::Vps.unscoped.where(object_state: ::Vps.object_states[:suspended]),
            changed: ::Vps.unscoped.where(
              object_state: ::Vps.object_states[:suspended]
            ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vpses.id = s.row_id")
                          .where('s.state = ?', ::Vps.object_states[:suspended])
                          .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                          .order('vpses.id')
          }
        },

        datasets: {
          all: ::Dataset.all,
          primary: ::Dataset.joins(dataset_in_pools: [:pool]).where(
            pools: { role: ::Pool.roles[:primary] }
          ).group('datasets.id'),
          hypervisor: ::Dataset.joins(dataset_in_pools: [:pool]).where(
            pools: { role: ::Pool.roles[:hypervisor] }
          ).group('datasets.id'),
          backup: ::Dataset.joins(dataset_in_pools: [:pool]).where(
            pools: { role: ::Pool.roles[:backup] }
          ).group('datasets.id')
        },

        snapshots: {
          all: ::Snapshot.all,
          new: ::Snapshot.where('DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t),
          primary: ::Snapshot.joins(dataset: [{ dataset_in_pools: [:pool] }]).where(
            pools: { role: ::Pool.roles[:primary] }
          ).group('snapshots.id'),
          hypervisor: ::Snapshot.joins(dataset: [{ dataset_in_pools: [:pool] }]).where(
            pools: { role: ::Pool.roles[:hypervisor] }
          ).group('snapshots.id'),
          backup: ::Snapshot.joins(dataset: [{ dataset_in_pools: [:pool] }]).where(
            pools: { role: ::Pool.roles[:backup] }
          ).group('snapshots.id')
        },

        downloads: {
          all: ::SnapshotDownload.all,
          new: ::SnapshotDownload.where(
            'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
          ),
          primary: ::SnapshotDownload.joins(:pool).where(
            pools: { role: ::Pool.roles[:primary] }
          ),
          hypervisor: ::SnapshotDownload.joins(:pool).where(
            pools: { role: ::Pool.roles[:hypervisor] }
          ),
          backup: ::SnapshotDownload.joins(:pool).where(
            pools: { role: ::Pool.roles[:backup] }
          )
        },

        chains: {
          total: chains,
          done: chains.where(state: ::TransactionChain.states[:done]),
          failed: chains.where(state: ::TransactionChain.states[:failed]),
          fatal: chains.where(state: ::TransactionChain.states[:fatal]),
          resolved: chains.where(state: ::TransactionChain.states[:resolved]),
          all_failed: chains.where('state >= ?', ::TransactionChain.states[:failed])
        },

        transactions: {
          total: trans,
          done: trans.where(done: 1),
          rollbacked: trans.where(done: 2),
          successful: trans.where(done: 1, status: 1),
          failed: trans.where(done: 1, status: 0),
          warning: trans.where(done: 1, status: 2),
          pending: trans.where(done: 0)
        },

        cluster_resources: {
          overused: ::UserClusterResource
            .joins(:cluster_resource_uses, :user)
            .select('user_cluster_resources.*, SUM(cluster_resource_uses.value) AS used_sum')
            .where(
              users: { object_state: 'active' },
              cluster_resource_uses: { confirmed: ::ClusterResourceUse.confirmed(:confirmed) }
            )
            .group('user_cluster_resources.user_id, user_cluster_resources.environment_id, user_cluster_resources.cluster_resource_id')
            .having('SUM(cluster_resource_uses.value) > user_cluster_resources.value')
        },

        backups: {
          old_latest_any_snapshot: ::Dataset
            .joins(dataset_in_pools: :dataset_in_pool_plans)
            .where('(SELECT COUNT(*) FROM snapshots s WHERE s.dataset_id = datasets.id AND s.created_at > DATE_SUB(NOW(), INTERVAL 3 DAY)) = 0')
            .group('datasets.id'),

          old_latest_backup_snapshot: ::DatasetInPool
            .joins(:dataset, :pool, :dataset_in_pool_plans)
            .where(pools: { role: ::Pool.roles[:backup] })
            .where('(
                SELECT dips2.id
                FROM dataset_in_pools dips2
                INNER JOIN pools p2 ON p2.id = dips2.pool_id
                WHERE dataset_id = datasets.id AND p2.role IN (0)
                LIMIT 1
              ) IS NOT NULL')
            .where('(
                SELECT COUNT(*)
                FROM snapshot_in_pools sips
                INNER JOIN snapshots s ON s.id = sips.snapshot_id
                WHERE
                  sips.dataset_in_pool_id = dataset_in_pools.id
                  AND s.created_at > DATE_SUB(NOW(), INTERVAL 3 DAY)
              ) = 0')
            .group('datasets.id'),

          too_many_in_hypervisor: ::DatasetInPool
            .select('dataset_in_pools.*, COUNT(snapshot_in_pools.id) AS snapshot_count')
            .joins(:dataset, :pool, :snapshot_in_pools)
            .where(pools: { role: ::Pool.roles[:hypervisor] })
            .group('datasets.id, pools.id')
            .having('snapshot_count > 2')
            .order(Arel.sql('COUNT(snapshot_in_pools.id) DESC')),

          too_many_in_backup: ::DatasetInPool
            .select('dataset_in_pools.*, COUNT(snapshot_in_pools.id) AS snapshot_count')
            .joins(:dataset, :pool, :snapshot_in_pools)
            .where(pools: { role: ::Pool.roles[:backup] })
            .group('datasets.id, pools.id')
            .having('snapshot_count > 20')
            .order(Arel.sql('COUNT(snapshot_in_pools.id) DESC'))
        },

        dataset_expansions: {
          active: ::DatasetExpansion
            .includes(:dataset, :vps)
            .joins(:vps, dataset: :user)
            .where(state: 'active')
            .where(users: { object_state: ::User.object_states[:active] })
            .where(vpses: { object_state: ::Vps.object_states[:active] })
            .order('over_refquota_seconds DESC'),

          new: ::DatasetExpansion
            .includes(:dataset, :vps)
            .where(state: 'active')
            .where('DATE_ADD(dataset_expansions.created_at, INTERVAL 1 DAY) >= ?', t)
            .order('dataset_expansions.created_at'),

          resolved: ::DatasetExpansion
            .includes(:dataset, :vps)
            .where(state: 'resolved')
            .where('DATE_ADD(dataset_expansions.updated_at, INTERVAL 1 DAY) >= ?', t)
            .order('dataset_expansions.updated_at')
        },

        oom_reports: {
          by_vps: ::Vps
            .select('vpses.*, SUM(oom_reports.`count`) AS oom_count')
            .joins(:oom_reports)
            .where(vpses: { object_state: [
                     ::Vps.object_states[:active],
                     ::Vps.object_states[:suspended]
                   ] })
            .where('DATE_ADD(oom_reports.created_at, INTERVAL 1 DAY) >= ?', t)
            .group('vpses.id')
            .having('oom_count > 0')
            .order(Arel.sql('SUM(oom_reports.`count`) DESC')),

          preventions: ::OomPrevention
            .where('DATE_ADD(oom_preventions.created_at, INTERVAL 1 DAY) >= ?', t)
            .order('created_at'),

          by_node: ::Node
            .select('nodes.*, SUM(oom_reports.`count`) AS oom_count')
            .joins(vpses: :oom_reports)
            .where(vpses: { object_state: [
                     ::Vps.object_states[:active],
                     ::Vps.object_states[:suspended]
                   ] })
            .where('DATE_ADD(oom_reports.created_at, INTERVAL 1 DAY) >= ?', t)
            .group('nodes.id')
            .having('oom_count > 0')
            .order(Arel.sql('SUM(oom_reports.`count`) DESC')),

          by_killed_name: ::OomReport
            .where('DATE_ADD(oom_reports.created_at, INTERVAL 1 DAY) >= ?', t)
            .group('killed_name')
            .sum(:count)
            .sort { |a, b| b[1] <=> a[1] }
        },

        incident_reports: {
          new: ::IncidentReport
            .includes(:user, :vps)
            .where('DATE_ADD(incident_reports.created_at, INTERVAL 1 DAY) >= ?', t)
            .order('incident_reports.detected_at')
        }
      }
    end
  end
end
