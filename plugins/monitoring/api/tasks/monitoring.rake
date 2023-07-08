namespace :vpsadmin do
  namespace :monitoring do
    desc 'Run monitoring checks'
    task :check do
      VpsAdmin::API::Plugins::Monitoring.monitors.each do |m|
        m.check
      end
    end

    desc 'Close inactive events'
    task :close do
      ::MonitoredEvent.where(
        state: %w(monitoring confirmed acknowledged ignored),
      ).where(
        'DATE_ADD(updated_at, INTERVAL 1 MONTH) < ?', Time.now.utc.strftime('%Y-%m-%d %H:%M:%S')
      ).each do |event|
        event.update!(state: 'closed')
      end
    end
  end
end
