require 'lib/handlers/migration'

module MigrationBackend
  class ExtToExtMigration < Migration
    def migrate_part2
      sync_private

      super
    end
  end
end
