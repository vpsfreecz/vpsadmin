module TransactionChains
  class Mail::DailyReport < ::TransactionChain
    label 'Daily report'
    allow_empty

    def link_chain(lang)
      now = Time.now.utc
      t = now.strftime('%Y-%m-%d %H:%M:%S')

      chains = ::TransactionChain.where(
          'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
      )
      trans = ::Transaction.where(
          'DATE_ADD(created_at, INTERVAL 1 DAY) > ?', t
      )

      mail(:daily_report, {
          language: lang,
          vars: {
              base_url: ::SysConfig.get('general_base_url'),
              
              date: {
                  start: (now - 24*60*60),
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
                      pools: {role: ::Pool.roles[:primary]}
                  ).group('datasets.id'),
                  hypervisor: ::Dataset.joins(dataset_in_pools: [:pool]).where(
                      pools: {role: ::Pool.roles[:hypervisor]}
                  ).group('datasets.id'),
                  backup: ::Dataset.joins(dataset_in_pools: [:pool]).where(
                      pools: {role: ::Pool.roles[:backup]}
                  ).group('datasets.id')
              },
              
              snapshots: {
                  all: ::Snapshot.all,
                  new: ::Snapshot.where('DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t),
                  primary: ::Snapshot.joins(dataset: [{dataset_in_pools: [:pool]}]).where(
                      pools: {role: ::Pool.roles[:primary]}
                  ).group('snapshots.id'),
                  hypervisor: ::Snapshot.joins(dataset: [{dataset_in_pools: [:pool]}]).where(
                      pools: {role: ::Pool.roles[:hypervisor]}
                  ).group('snapshots.id'),
                  backup: ::Snapshot.joins(dataset: [{dataset_in_pools: [:pool]}]).where(
                      pools: {role: ::Pool.roles[:backup]}
                  ).group('snapshots.id'),
              },

              downloads: {
                  all: ::SnapshotDownload.all,
                  new: ::SnapshotDownload.where(
                      'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
                  ),
                  primary: ::SnapshotDownload.joins(:pool).where(
                      pools: {role: ::Pool.roles[:primary]}
                  ),
                  hypervisor: ::SnapshotDownload.joins(:pool).where(
                      pools: {role: ::Pool.roles[:hypervisor]}
                  ),
                  backup: ::SnapshotDownload.joins(:pool).where(
                      pools: {role: ::Pool.roles[:backup]}
                  ),
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
              }

          }
      })
    end
  end
end
