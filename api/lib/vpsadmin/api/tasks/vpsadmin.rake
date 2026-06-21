namespace :vpsadmin do
  desc 'Open an interactive shell'
  task :shell do
    require 'pry'
    pry # rubocop:disable Lint/Debugger
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

  namespace :auth do
    desc 'Close expired authentication processes'
    task :close_expired do
      puts 'Close expired authentication processes'
      VpsAdmin::API::Tasks.run(:authentication, :close_expired)
    end

    desc 'Report failed login attempts'
    task :report_failed_logins do
      puts 'Reporting failed login attempts'
      VpsAdmin::API::Tasks.run(:authentication, :report_failed_logins)
    end
  end

  namespace :user_session do
    desc 'Close expired user sessions'
    task :close_expired do
      puts 'Close expired user sessions'
      VpsAdmin::API::Tasks.run(:user_session, :close_expired)
    end
  end

  namespace :mail do
    desc 'Process mail from configured mailboxes'
    task :process do
      VpsAdmin::API::Tasks.run(:mail, :process)
    end
  end

  namespace :event_delivery do
    desc 'Deliver released event e-mails once'
    task :emails do
      VpsAdmin::API::Tasks.run(:event_delivery, :deliver_emails)
    end

    desc 'Deliver released event webhooks once'
    task :webhooks do
      VpsAdmin::API::Tasks.run(:event_delivery, :deliver_webhooks)
    end

    desc 'Deliver released event Telegram messages once'
    task :telegrams do
      VpsAdmin::API::Tasks.run(:event_delivery, :deliver_telegrams)
    end
  end

  namespace :telegram do
    desc 'Poll Telegram bot updates for notification receiver pairing'
    task :poll_pairing_updates do
      VpsAdmin::API::Tasks.run(:telegram, :poll_pairing_updates)
    end
  end

  namespace :notification_templates do
    desc 'Install built-in notification templates'
    task :install_defaults do
      puts 'Install built-in notification templates'
      result = VpsAdmin::API::NotificationTemplates.install_defaults!
      puts "Created #{result[:templates_created]} templates and " \
           "#{result[:variants_created]} variants"
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

    desc 'Prune VPS status logs'
    task :prune_status_logs do
      puts 'Pruning VPS status log'
      VpsAdmin::API::Tasks.run(:vps, :prune_status_logs)
    end
  end

  namespace :dataset do
    desc 'Remove old dataset property logs'
    task :prune_property_logs do
      puts 'Pruning dataset property logs'
      VpsAdmin::API::Tasks.run(:dataset, :prune_property_logs)
    end
  end

  namespace :snapshot do
    desc 'Remove unused snapshot clones'
    task :purge_clones do
      puts 'Purge snapshot clones'
      VpsAdmin::API::Tasks.run(:snapshot, :purge_clones)
    end
  end

  namespace :incident_report do
    desc 'Process incident reports'
    task :process do
      VpsAdmin::API::Tasks.run(:incident_report, :process)
    end
  end

  namespace :oom_report do
    desc 'Notify users about stale OOM reports'
    task :notify do
      puts 'Notifying users about stale OOM reports'
      VpsAdmin::API::Tasks.run(:oom_report, :notify)
    end

    desc 'Run OOM reports pipeline'
    task run: %i[notify]

    desc 'Remove old OOM reports'
    task :prune do
      puts 'Pruning OOM reports'
      VpsAdmin::API::Tasks.run(:oom_report, :prune)
    end
  end

  namespace :prometheus do
    namespace :export do
      task all: %i[base dns_records]

      desc 'Generate text files with vpsAdmin metrics for prometheus'
      task :base do
        VpsAdmin::API::Tasks.run(:prometheus, :export_base)
      end

      desc 'Generate text files with DNS record metrics for prometheus'
      task :dns_records do
        VpsAdmin::API::Tasks.run(:prometheus, :export_dns_records)
      end
    end
  end

  namespace :dataset_expansion do
    desc 'Process dataset expansion events'
    task :process do
      puts 'Process dataset expansion events'
      VpsAdmin::API::Tasks.run(:dataset_expansion, :process_events)
    end

    desc 'Stop VPS with datasets over quota'
    task :enforce do
      puts 'Stopping VPS with datasets over quota'
      VpsAdmin::API::Tasks.run(:dataset_expansion, :stop_vps)
    end

    desc 'Shrink datasets that have returned the extra space'
    task :resolve do
      puts 'Return extra space where possible'
      VpsAdmin::API::Tasks.run(:dataset_expansion, :resolve_datasets)
    end

    desc 'Run whole dataset expansion pipeline'
    task run: %i[process enforce resolve]
  end

  namespace :dns do
    desc 'Check DNS servers return configured reverse records'
    task :check_reverse_records do
      VpsAdmin::API::Tasks.run(:dns, :check_reverse_records)
    end

    desc 'Prune DNS transfer logs'
    task :prune_transfer_logs do
      puts 'Pruning DNS transfer logs'
      VpsAdmin::API::Tasks.run(:dns, :prune_transfer_logs)
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
