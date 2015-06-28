namespace :vpsadmin do
  desc 'Progress state of expired objects'
  task :lifetimes_progress do
    puts 'Progress lifetimes'
    VpsAdmin::API::Tasks.run(:lifetime, :progress)
  end

  desc 'Mail users regarding objects nearing expiration'
  task :lifetimes_mail do
    puts 'Mail users regarding expiring objects'
    VpsAdmin::API::Tasks.run(:lifetime, :mail_expiration)
  end
end
