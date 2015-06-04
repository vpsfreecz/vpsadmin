namespace :vpsadmin do
  desc 'Progress state of expired objects'
  task :lifetimes_progress do
    puts 'Progress lifetimes'
    VpsAdmin::API::Tasks.run(:lifetimes, :progress)
  end
end
