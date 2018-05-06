module VpsAdmin::API::Plugin
  class Migrator < ActiveRecord::Migrator
    class << self
      attr_accessor :current_plugin

      def migrate_plugin(plugin, version)
        self.current_plugin = plugin
        return if current_version(plugin) == version
        migrate(plugin.migration_directory, version)
      end

      def rollback_plugin(plugin, step)
        self.current_plugin = plugin
        rollback(plugin.migration_directory, step)
      end

      def current_version(plugin = current_plugin)
        ::ActiveRecord::Base.connection.select_values(
          "SELECT version FROM #{schema_migrations_table_name}"
        ).delete_if { |v| v.match(/-#{plugin.id}$/) == nil }.map(&:to_i).max || 0
      end
    end

    def migrated
      sm_table = self.class.schema_migrations_table_name
      ::ActiveRecord::Base.connection.select_values(
        "SELECT version FROM #{sm_table}"
      ).delete_if { |v| v.match(/-#{self.class.current_plugin.id}$/) == nil }.map(&:to_i).sort
    end

    def record_version_state_after_migrating(version)
      super(version.to_s + "-" + self.class.current_plugin.id.to_s)
    end
  end
end
