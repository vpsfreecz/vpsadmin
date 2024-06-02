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
  end
end
