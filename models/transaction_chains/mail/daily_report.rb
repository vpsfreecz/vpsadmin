module TransactionChains
  class Mail::DailyReport < ::TransactionChain
    label 'Daily report'
    allow_empty

    def link_chain
      now = Time.now.utc
      t = now.strftime('%Y-%m-%d %H:%M:%S')

      chains = ::TransactionChain.where(
          'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
      )
      trans = ::Transaction.where(
          'DATE_ADD(created_at, INTERVAL 1 DAY) > ?', t
      )

      mail(:daily_report, {
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
                      ).order('m_id')
                  },

                  active: {
                      all: ::User.unscoped.where(object_state: ::User.object_states[:active]),
                      changed: ::User.unscoped.where(
                          object_state: ::User.object_states[:active]
                      ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND members.m_id = s.row_id")
                      .where('s.state = ?', ::User.object_states[:active])
                      .where('s.created_at != members.created_at')
                      .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                      .order('members.m_id')
                  },

                  soft_deleted: {
                      all: ::User.unscoped.where(object_state: ::User.object_states[:soft_delete]),
                      changed: ::User.unscoped.where(
                          object_state: ::User.object_states[:soft_delete]
                      ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND members.m_id = s.row_id")
                      .where('s.state = ?', ::User.object_states[:soft_delete])
                      .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                      .order('members.m_id')
                  },
                  
                  hard_deleted: {
                      all: ::User.unscoped.where(object_state: ::User.object_states[:hard_delete]),
                      changed: ::User.unscoped.where(
                          object_state: ::User.object_states[:hard_delete]
                      ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND members.m_id = s.row_id")
                      .where('s.state = ?', ::User.object_states[:hard_delete])
                      .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                      .order('members.m_id')
                  },

                  suspended: {
                      all: ::User.unscoped.where(object_state: ::User.object_states[:suspended]),
                      changed: ::User.unscoped.where(
                          object_state: ::User.object_states[:suspended]
                      ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND members.m_id = s.row_id")
                      .where('s.state = ?', ::User.object_states[:suspended])
                      .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                      .order('members.m_id')
                  }
              },

              vps: {
                  new: {
                      changed: ::Vps.existing.where(
                          'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
                      ).order('m_id')
                  },

                  active: {
                      all: ::Vps.unscoped.where(object_state: ::Vps.object_states[:active]),
                      changed: ::Vps.unscoped.where(
                          object_state: ::Vps.object_states[:active]
                      ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vps.vps_id = s.row_id")
                      .where('s.state = ?', ::Vps.object_states[:active])
                      .where('s.created_at != vps.created_at')
                      .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                      .order('vps.vps_id')
                  },

                  soft_deleted: {
                      all: ::Vps.unscoped.where(object_state: ::Vps.object_states[:soft_delete]),
                      changed: ::Vps.unscoped.where(
                          object_state: ::Vps.object_states[:soft_delete]
                      ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vps.vps_id = s.row_id")
                      .where('s.state = ?', ::Vps.object_states[:soft_delete])
                      .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                      .order('vps.vps_id')
                  },

                  hard_deleted: {
                      all: ::Vps.unscoped.where(object_state: ::Vps.object_states[:hard_delete]),
                      changed: ::Vps.unscoped.where(
                          object_state: ::Vps.object_states[:hard_delete]
                      ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vps.vps_id = s.row_id")
                      .where('s.state = ?', ::Vps.object_states[:hard_delete])
                      .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                      .order('vps.vps_id')
                  },

                  suspended: {
                      all: ::Vps.unscoped.where(object_state: ::Vps.object_states[:suspended]),
                      changed: ::Vps.unscoped.where(
                          object_state: ::Vps.object_states[:suspended]
                      ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vps.vps_id = s.row_id")
                      .where('s.state = ?', ::Vps.object_states[:suspended])
                      .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                      .order('vps.vps_id')
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
                  done: trans.where(t_done: 1),
                  rollbacked: trans.where(t_done: 2),
                  successful: trans.where(t_done: 1, t_success: 1),
                  failed: trans.where(t_done: 1, t_success: 0),
                  warning: trans.where(t_done: 1, t_success: 2),
                  pending: trans.where(t_done: 0)
              }

          }
      })
    end
  end
end
