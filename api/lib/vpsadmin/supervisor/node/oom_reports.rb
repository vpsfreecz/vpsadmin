require_relative 'base'

module VpsAdmin::Supervisor
  class Node::OomReports < Node::Base
    def start
      exchange = channel.direct(exchange_name)
      queue = channel.queue(queue_name('oom_reports'))

      queue.bind(exchange, routing_key: 'oom_reports')

      queue.subscribe do |_delivery_info, _properties, payload|
        report = JSON.parse(payload)
        save_report(report)
      end
    end

    protected
    def save_report(report)
      vps = ::Vps.find_by(id: report['vps_id'], node_id: node.id)
      return if vps.nil?

      invoked_by_name = report.fetch('invoked_by_name')
      killed_name = report.fetch('killed_name')

      new_report = ::OomReport.create!(
        vps: vps,
        cgroup: report.fetch('cgroup')[0..254],
        invoked_by_pid: report.fetch('invoked_by_pid'),
        invoked_by_name: invoked_by_name && invoked_by_name[0..49],
        killed_pid: report.fetch('killed_pid'),
        killed_name: killed_name && killed_name[0..49],
        count: report.fetch('count'),
        created_at: Time.at(report.fetch('time')),
        processed: true,
      )

      new_report.oom_report_usages.insert_all(
        report.fetch('usage').map do |type, attrs|
          {
            memtype: type,
            usage: attrs['usage'],
            limit: attrs['limit'],
            failcnt: attrs['failcnt'],
          }
        end
      )

      new_report.oom_report_stats.insert_all(
        report.fetch('stats').map do |param, value|
          {
            parameter: param,
            value: value,
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
            pgtables_bytes: task.fetch('pgtables_bytes'),
            swapents: task.fetch('swapents'),
            oom_score_adj: task.fetch('oom_score_adj'),
          }
        end
      )
    end
  end
end
