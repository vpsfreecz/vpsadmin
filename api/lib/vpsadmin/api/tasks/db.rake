namespace :db do
  namespace :seed do
    desc 'Seed database with SEED_FILE'
    task file: :environment do
      file =
        if ENV['SEED_FILE'].start_with?('/')
          ENV['SEED_FILE']
        else
          File.join(VpsAdmin::API.root, 'db', 'seeds', "#{ENV['SEED_FILE']}.rb")
        end

      puts "Seeding #{file}"
      load(file)
    end
  end
end
