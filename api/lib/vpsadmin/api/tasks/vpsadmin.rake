namespace :vpsadmin do
  desc 'Open an interactive shell'
  task :shell do
    require 'pry'
    pry
  end

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

  namespace :user_session do
    desc 'Close expired user sessions'
    task :close_expired do
      puts "Close expired user sessions"
      VpsAdmin::API::Tasks.run(:user_session, :close_expired)
    end
  end

  desc 'Mail daily report'
  task :mail_daily_report do
    puts 'Mail daily report'
    VpsAdmin::API::Tasks.run(:mail, :daily_report)
  end

  namespace :vps do
    namespace :migration do
      desc 'Execute VPS migration plans'
      task :run_plans do
        puts 'Execute VPS migration plans'
        VpsAdmin::API::Tasks.run(:vps_migration, :run_plans)
      end
    end
  end

  namespace :plugins do
    desc 'List installed plugins'
    task :list do
      puts 'List installed plugins'
      VpsAdmin::API::Tasks.run(:plugins, :list)
    end

    desc 'Show migration status'
    task :status do
      puts 'Show migration status'
      VpsAdmin::API::Tasks.run(:plugins, :status)
    end

    desc 'Run plugin migrations'
    task :migrate do
      puts 'Run plugin migrations'
      VpsAdmin::API::Tasks.run(:plugins, :migrate)
    end
    
    desc 'Rollback plugin migrations'
    task :rollback do
      puts 'Run plugin rollback'
      VpsAdmin::API::Tasks.run(:plugins, :rollback)
    end
    
    desc 'Rollback all plugin migrations'
    task :uninstall do
      puts 'Rollback all plugin migrations'
      VpsAdmin::API::Tasks.run(:plugins, :uninstall)
    end
  end
end
