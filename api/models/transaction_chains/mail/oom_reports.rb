module TransactionChains
  class Mail::OomReports < ::TransactionChain
    label 'OOM Reports'
    allow_empty

    # @param vpses [Array<::Vps>]
    # @param cooldown [Integer] seconds from last report to wait before notifying
    #                           the user again
    def link_chain(vpses, cooldown: 3*60*60)
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

      if last_reported_oom && last_reported_oom.reported_at > (t - cooldown)
        return
      end

      reports = vps.oom_reports.where(reported_at: nil).order('oom_reports.created_at')

      if last_reported_oom
        reports = reports.where('oom_reports.id > ?', last_reported_oom.id)
      end

      mail(:vps_oom_report, {
        user: vps.user,
        vars: {
          base_url: ::SysConfig.get(:webui, :base_url),
          vps: vps,
          all_oom_reports: reports,
          selected_oom_reports: reports[0..29],
        },
      })

      reports.update_all(reported_at: t)
    end
  end
end
