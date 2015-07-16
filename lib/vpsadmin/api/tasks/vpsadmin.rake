namespace :vpsadmin do
  namespace :lifetimes do
    desc 'Progress state of expired objects'
    task :progress do
      puts 'Progress lifetimes'
      VpsAdmin::API::Tasks.run(:lifetime, :progress)
    end

    desc 'Mail users regarding objects nearing expiration'
    task :mail do
      puts 'Mail users regarding expiring objects'
      VpsAdmin::API::Tasks.run(:lifetime, :mail_expiration)
    end
  end

  desc 'Mail daily report'
  task :mail_daily_report do
    puts 'Mail daily report'
    VpsAdmin::API::Tasks.run(:mail, :daily_report)
  end
end
