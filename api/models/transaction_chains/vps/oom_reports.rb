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

      reports = vps.oom_reports.where(reported_at: nil, ignored: false).order('oom_reports.created_at')

      reports = reports.where('oom_reports.id > ?', last_reported_oom.id) if last_reported_oom
      return unless reports.exists?

      selected_reports = reports.limit(30).to_a
      selected_report_ids = selected_reports.map(&:id)
      report_count = reports.count
      all_oom_count = reports.sum(:count)
      selected_oom_count = selected_reports.sum(&:count)

      event = route_event!(
        'vps.oom_report',
        user: vps.user,
        vps:,
        source: selected_reports.first,
        subject: "OOM report for VPS ##{vps.id}",
        summary: "vpsAdmin recorded #{all_oom_count} out-of-memory events",
        parameters: oom_event_parameters(
          reports: selected_reports,
          last_reported_id: last_reported_oom&.id,
          batch_reported_at: t,
          report_count:,
          selected_report_ids:,
          all_oom_count:,
          selected_oom_count:
        )
      )
      ensure_email_deliveries_queued!(event)

      reports.update_all(reported_at: t)
    end

    def ensure_email_deliveries_queued!(event)
      failed = event
               .event_deliveries
               .where(action: 'email', state: 'failed')
               .order(:id)
               .first
      return unless failed

      raise "failed to prepare OOM report e-mail delivery: #{failed.error_summary}"
    end

    def oom_event_parameters(reports:, last_reported_id:, batch_reported_at:, report_count:,
                             selected_report_ids:, all_oom_count:, selected_oom_count:)
      cgroups = reports.map(&:cgroup).uniq
      killed_names = reports.map(&:killed_name).compact.uniq

      {
        stage: 'notification',
        cgroup: cgroups.one? ? cgroups.first : cgroups.join(', '),
        cgroups:,
        count: all_oom_count,
        oom_count: all_oom_count,
        killed_name: killed_names.one? ? killed_names.first : nil,
        report_count:,
        selected_report_count: selected_report_ids.count,
        selected_oom_count:,
        last_reported_id:,
        batch_reported_at: batch_reported_at.iso8601,
        selected_report_ids:
      }
    end
  end
end
