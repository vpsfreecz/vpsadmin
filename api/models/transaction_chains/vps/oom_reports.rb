module TransactionChains
  class Vps::OomReports < ::TransactionChain
    label 'OOM Reports'
    allow_empty

    # @param vpses [Array<::Vps>]
    # @param cooldown [Integer] seconds from last report to wait before notifying
    #                           the user again
    def link_chain(vpses, cooldown: 3 * 60 * 60)
      vpses.each do |vps|
        notify_vps_owner(vps, cooldown)
      end
    end

    protected

    def notify_vps_owner(vps, cooldown)
      last_reported_oom = vps.oom_reports
                             .where.not(reported_at: nil)
                             .order('oom_reports.id DESC')
                             .take

      t = Time.now

      return if last_reported_oom && last_reported_oom.reported_at > (t - cooldown)

      reports = vps.oom_reports.where(reported_at: nil).order('oom_reports.created_at')

      reports = reports.where('oom_reports.id > ?', last_reported_oom.id) if last_reported_oom

      selected_reports = reports.limit(30)

      mail(:vps_oom_report, {
             user: vps.user,
             vars: {
               base_url: ::SysConfig.get(:webui, :base_url),
               vps: vps,
               all_oom_reports: reports,
               all_oom_count: reports.sum(:count),
               selected_oom_reports: selected_reports,
               selected_oom_count: selected_reports.pluck(:count).sum
             }
           })

      reports.update_all(reported_at: t)
    end
  end
end
