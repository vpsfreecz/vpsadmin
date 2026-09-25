namespace :db do
  namespace :bootstrap do
    desc 'Create the storage freeze control after loading a fresh schema'
    task storage_freeze_control: :environment do
      # db:schema:load marks the foundation migration applied without running
      # its data insert. Leave an existing control and its audit intact.
      ActiveRecord::Base.connection.execute(<<~SQL)
        INSERT INTO storage_freeze_controls
          (id, mode, epoch, created_at, updated_at)
        VALUES (1, 0, 0, UTC_TIMESTAMP(), UTC_TIMESTAMP())
        ON DUPLICATE KEY UPDATE id = id
      SQL
    end
  end

  namespace :seed do
    desc 'Seed database with SEED_FILE'
    task file: :environment do
      VpsAdmin::API::Tasks.run(:db, :seed_file)
    end
  end
end
