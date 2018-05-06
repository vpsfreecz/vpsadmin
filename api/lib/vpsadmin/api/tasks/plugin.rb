module VpsAdmin::API::Tasks
  class Plugin < Base
    # List installed plugins
    def list
      puts sprintf('%-20s %-20s %10s  %-20s', 'ID', 'NAME', 'VERSION', 'COMPONENTS')
      VpsAdmin::API::Plugin.registered.each do |id, p|
        puts sprintf(
          '%-20s %-20s %10s  %-20s',
          p.id,
          p.name,
          p.version,
          p.components && p.components.join(',')
        )
      end
    end

    # Show plugin status
    # Accepts the following environment variables:
    # [PLUGIN]: plugin name, required
    def status
      required_env('PLUGIN')
      plugin = VpsAdmin::API::Plugin.registered[ENV['PLUGIN'].to_sym]
      fail 'plugin not found' unless plugin

      unless ActiveRecord::Base.connection.table_exists?(ActiveRecord::Migrator.schema_migrations_table_name)
        puts 'Schema migrations table does not exist yet.'
        return
      end

      db_list = ActiveRecord::Base.connection.select_values(
          "SELECT version FROM #{ActiveRecord::Migrator.schema_migrations_table_name}"
      ).delete_if do |v|
        v.match(/-#{plugin.id}$/).nil?

      end.map! do |version|
        ActiveRecord::SchemaMigration.normalize_migration_number(version)
      end

      file_list = []

      Dir.foreach(plugin.migration_directory) do |file|
        # match "20091231235959_some_name.rb" and "001_some_name.rb" pattern
        if match_data = /^(\d{3,})_(.+)\.rb$/.match(file)
          version = ActiveRecord::SchemaMigration.normalize_migration_number(match_data[1])
          status = db_list.delete(version) ? 'up' : 'down'
          file_list << [status, version, match_data[2].humanize]
        end
      end

      db_list.map! do |version|
        ['up', version, '********** NO FILE **********']
      end

      # output
      puts
      puts "database: #{ActiveRecord::Base.connection_config[:database]}"
      puts "plugin:   #{plugin.id}\n\n"
      puts "#{'Status'.center(8)}  #{'Migration ID'.ljust(14)}  Migration Name"
      puts "-" * 50
      (db_list + file_list).sort_by { |migration| migration[1] }.each do |migration|
        puts "#{migration[0].center(8)}  #{migration[1].ljust(14)}  #{migration[2]}"
      end
      puts
    end

    # Run db migrations for plugins
    #
    # Accepts the following environment variables:
    # [PLUGIN]: plugin name, optional
    # [VERSION]: target version, requires plugin name
    def migrate
      if ENV['PLUGIN'].nil?
        fail 'VERSION requires PLUGIN to be set' if ENV['VERSION']

        VpsAdmin::API::Plugin.registered.each_value do |p|
          puts "Migrating plugin #{p.id}"
          p.migrate
        end

      else
        v = ENV['VERSION'].nil? ? nil : ENV['VERSION'].to_i
        plugin = VpsAdmin::API::Plugin.registered[ENV['PLUGIN'].to_sym]
        fail 'plugin not found' unless plugin

        plugin.migrate(v)
      end
    end

    # Rollback plugin migrations
    #
    # Accepts the following environment variables:
    # [PLUGIN]: plugin name, required
    # [STEP]: how many migrations to rollback, defaults to 1
    def rollback
      required_env('PLUGIN')
      plugin = VpsAdmin::API::Plugin.registered[ENV['PLUGIN'].to_sym]
      fail 'plugin not found' unless plugin

      step = ENV['STEP'] ? ENV['STEP'].to_i : 1
      plugin.rollback(step)
    end

    # Rollback all plugin migrations
    #
    # Accepts the following environment variables:
    # [PLUGIN]: plugin name, required
    def uninstall
      required_env('PLUGIN')
      plugin = VpsAdmin::API::Plugin.registered[ENV['PLUGIN'].to_sym]
      fail 'plugin not found' unless plugin

      plugin.rollback(plugin.migrations.count)
    end
  end
end
