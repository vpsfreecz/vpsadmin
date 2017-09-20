namespace :vpsadmin do
  namespace :monitoring do
    task :check do
      VpsAdmin::API::Plugins::Monitoring.monitors.each do |m|
        m.check
      end
    end
  end
end
