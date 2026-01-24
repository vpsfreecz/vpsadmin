namespace :db do
  namespace :seed do
    desc 'Seed database with SEED_FILE'
    task file: :environment do
      VpsAdmin::API::Tasks.run(:db, :seed_file)
    end
  end
end
