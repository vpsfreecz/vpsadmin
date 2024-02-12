module VpsAdmin::API::Plugin
  class MigrationContext < ActiveRecord::MigrationContext
    def up(target_version = nil, &)
      selected_migrations =
        if block_given?
          migrations.select(&)
        else
          migrations
        end
      Migrator.new(:up, selected_migrations, schema_migration, internal_metadata, target_version).migrate
    end

    def down(target_version = nil, &)
      selected_migrations =
        if block_given?
          migrations.select(&)
        else
          migrations
        end
      Migrator.new(:down, selected_migrations, schema_migration, internal_metadata, target_version).migrate
    end

    def run(direction, target_version)
      Migrator.new(direction, migrations, schema_migration, internal_metadata, target_version).run
    end

    def open
      Migrator.new(:up, migrations, schema_migration, internal_metadata)
    end

    def current_version
      Migrator.current_version
    end
  end

  class Migrator < ActiveRecord::Migrator
    cattr_accessor :current_plugin

    class << self
      def migrate_plugin(plugin, version)
        self.current_plugin = plugin
        return if current_version(plugin) == version

        MigrationContext.new(
          plugin.migration_directory,
          ::ActiveRecord::Base.connection.schema_migration
        ).migrate(version)
      end

      def rollback_plugin(plugin, steps)
        self.current_plugin = plugin
        return if current_version(plugin) == version

        MigrationContext.new(
          plugin.migration_directory,
          ::ActiveRecord::Base.connection.schema_migration
        ).rollback(steps)
      end

      def get_all_versions(plugin = current_plugin)
        @all_versions ||= {}
        @all_versions[plugin.id.to_s] ||= begin
          sm_table = ::ActiveRecord::Base.connection.schema_migration.table_name
          migration_versions  = ActiveRecord::Base.connection.select_values("SELECT version FROM #{sm_table}")
          versions_by_plugins = migration_versions.group_by { |version| version.match(/-(.*)$/).try(:[], 1) }
          @all_versions       = versions_by_plugins.transform_values! { |versions| versions.map!(&:to_i).sort! }
          @all_versions[plugin.id.to_s] || []
        end
      end

      def current_version(plugin = current_plugin)
        get_all_versions(plugin).last || 0
      end
    end

    def load_migrated
      @migrated_versions = Set.new(self.class.get_all_versions(current_plugin))
    end

    def record_version_state_after_migrating(version)
      super("#{version.to_s}-#{current_plugin.id.to_s}")
    end
  end
end
