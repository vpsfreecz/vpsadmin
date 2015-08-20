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
                  new: ::User.existing.where(
                      'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
                  ).order('m_id'),

                  deleted: ::User.unscoped.where(
                      object_state: ::User.object_states[:soft_delete]
                  ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND members.m_id = s.row_id")
                  .where('s.state = ?', ::User.object_states[:soft_delete])
                  .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                  .order('members.m_id'),

                  suspended: ::User.unscoped.where(
                      object_state: ::User.object_states[:suspended]
                  ).joins("INNER JOIN object_states s ON s.class_name = 'User' AND members.m_id = s.row_id")
                  .where('s.state = ?', ::User.object_states[:suspended])
                  .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                  .order('members.m_id')
              },

              vps: {
                  new: ::Vps.existing.where(
                      'DATE_ADD(created_at, INTERVAL 1 DAY) >= ?', t
                  ).order('m_id'),

                  deleted: ::Vps.unscoped.where(
                      object_state: ::Vps.object_states[:soft_delete]
                  ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vps.vps_id = s.row_id")
                  .where('s.state = ?', ::Vps.object_states[:soft_delete])
                  .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                  .order('vps.vps_id'),

                  suspended: ::Vps.unscoped.where(
                      object_state: ::Vps.object_states[:suspended]
                  ).joins("INNER JOIN object_states s ON s.class_name = 'Vps' AND vps.vps_id = s.row_id")
                  .where('s.state = ?', ::Vps.object_states[:suspended])
                  .where('DATE_ADD(s.created_at, INTERVAL 1 DAY) >= ?', t)
                  .order('vps.vps_id')
                  
              },

              chains: {
                  total: chains,
                  done: chains.where(state: ::TransactionChain.states[:done]),
                  failed: chains.where(state: ::TransactionChain.states[:failed]),
                  fatal: chains.where(state: ::TransactionChain.states[:fatal]),
                  resolved: chains.where(state: ::TransactionChain.states[:resolved])
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
