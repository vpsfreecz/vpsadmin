namespace :vpsadmin do
  namespace :monitoring do
    desc 'Run monitoring checks'
    task :check do
      VpsAdmin::API::Plugins::Monitoring.monitors.each(&:check)
    end

    desc 'Close inactive events'
    task :close do
      ::MonitoredEvent.where(
        state: %w[monitoring confirmed acknowledged ignored]
      ).where(
        'DATE_ADD(updated_at, INTERVAL 1 MONTH) < ?', Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      ).each do |event|
        event.update!(state: 'closed')
      end
    end

    desc 'Delete old events'
    task :prune do
      n_days = ENV['DAYS'] ? ENV['DAYS'].to_i : 365
      cnt = 0

      loop do
        any = false

        ::MonitoredEvent.where(
          state: %w[unconfirmed closed]
        ).where('created_at < ?', n_days.day.ago).limit(10_000).each do |event|
          any = true
          event.destroy!
          cnt += 1
        end

        break unless any
      end

      puts "Deleted #{cnt} monitored events"
    end

    desc 'Reset DNS secondary transfer monitor history for a monitor object class'
    task :reset_dns_secondary_transfer_failure, [:class_name] do |_task, args|
      unless ENV['CONFIRM'] == '1'
        raise 'Set CONFIRM=1 after stopping monitoring-event writers'
      end

      class_name = args.fetch(:class_name).to_s
      unless %w[DnsServerZone DnsZone].include?(class_name)
        raise ArgumentError, 'class_name must be DnsServerZone or DnsZone'
      end

      cnt = 0
      ::MonitoredEvent
        .where(
          monitor_name: 'dns_secondary_transfer_failure',
          class_name:
        )
        .in_batches do |events|
          ::MonitoredEvent.transaction do
            ids = events.lock.pluck(:id)
            ::MonitoredEventState.where(monitored_event_id: ids).delete_all
            ::MonitoredEventLog.where(monitored_event_id: ids).delete_all
            cnt += ::MonitoredEvent.where(id: ids).delete_all
          end
        end

      puts "Deleted #{cnt} #{class_name} DNS secondary transfer monitored events"
    end
  end
end
