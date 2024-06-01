require_relative 'base'

module VpsAdmin::Supervisor
  class Node::OomReports < Node::Base
    # Number of OOMs in one report that is considered too high, inclusive
    HIGHRATE = 1000

    # Number of seconds into the past to check for high-rate reports
    PERIOD = 10 * 60

    # Number of high-rate reports that trigger preventive action
    THRESHOLD = 5

    # Number of seconds in between preventive actions for one VPS
    PREVENTION_COOLDOWN = 5 * 60

    # Number of seconds into the past to check for previous preventions
    PREVENTION_PERIOD = 30 * 60

    # Number of preventive actions within {PREVENTION_PERIOD} that trigger VPS stop
    PREVENTION_THRESHOLD = 3

    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(
        queue_name('oom_reports'),
        durable: true,
        arguments: { 'x-queue-type' => 'quorum' }
      )

      queue.bind(exchange, routing_key: 'oom_reports')

      queue.subscribe do |_delivery_info, _properties, payload|
        data = JSON.parse(payload)
        report = save_report(data)

        if report.count >= THRESHOLD
          handle_abuser(report.vps)
        end
      end
    end

    protected

    def save_report(report)
      vps = ::Vps.find_by(id: report['vps_id'], node_id: node.id)
      return if vps.nil?

      invoked_by_name = report.fetch('invoked_by_name')
      killed_name = report.fetch('killed_name')

      new_report = ::OomReport.create!(
        vps:,
        cgroup: report.fetch('cgroup')[0..254],
        invoked_by_pid: report.fetch('invoked_by_pid'),
        invoked_by_name: invoked_by_name && invoked_by_name[0..49],
        killed_pid: report.fetch('killed_pid'),
        killed_name: killed_name && killed_name[0..49],
        count: report.fetch('count'),
        created_at: Time.at(report.fetch('time')),
        processed: true
      )

      new_report.oom_report_usages.insert_all(
        report.fetch('usage').map do |type, attrs|
          {
            memtype: type,
            usage: attrs['usage'],
            limit: attrs['limit'],
            failcnt: attrs['failcnt']
          }
        end
      )

      new_report.oom_report_stats.insert_all(
        report.fetch('stats').map do |param, value|
          {
            parameter: param,
            value:
          }
        end
      )

      new_report.oom_report_tasks.insert_all(
        report.fetch('tasks').map do |task|
          {
            host_pid: task.fetch('pid'),
            vps_pid: task.fetch('vps_pid'),
            name: task.fetch('name')[0..49],
            host_uid: task.fetch('uid'),
            vps_uid: task.fetch('vps_uid'),
            tgid: task.fetch('tgid'),
            total_vm: task.fetch('total_vm'),
            rss: task.fetch('rss'),
            rss_anon: task.fetch('rss_anon', nil),
            rss_file: task.fetch('rss_file', nil),
            rss_shmem: task.fetch('rss_shmem', nil),
            pgtables_bytes: task.fetch('pgtables_bytes'),
            swapents: task.fetch('swapents'),
            oom_score_adj: task.fetch('oom_score_adj')
          }
        end
      )

      new_report
    end

    def handle_abuser(vps)
      now = Time.now.utc
      since = now - PERIOD

      reports_in_period = ::OomReport
                          .where(vps:)
                          .where('created_at >= ?', since)

      if !vps.is_running? || reports_in_period.where('`count` >= ?', HIGHRATE).count < THRESHOLD
        return
      end

      last_prevention = vps.oom_preventions.order('id DESC').take

      if last_prevention && last_prevention.created_at + PREVENTION_COOLDOWN > now
        return
      end

      preventions_within_period = vps.oom_preventions.where(
        'created_at > ?',
        now - PREVENTION_PERIOD
      )

      action =
        if preventions_within_period.count >= PREVENTION_THRESHOLD
          :stop
        else
          :restart
        end

      begin
        TransactionChains::Vps::OomPrevention.fire2(
          kwargs: {
            vps:,
            action:,
            ooms_in_period: reports_in_period.sum(:count),
            period_seconds: PERIOD
          }
        )
        puts "VPS #{vps.id} -> #{action}"
      rescue ::ResourceLocked
        puts "VPS #{vps.id} locked, would #{action} otherwise"
      end
    end
  end
end
