require 'lib/handlers/migration'

module MigrationBackend
  class ZfsToExtMigration < Migration
    def migrate_part1
      copy_configs
      create_root
      sync_private
    end

    def migrate_part2
      sync_private

      vzctl(:set, @veid, {:root => @vps.ve_root, :private => @vps.ve_private}, true)

      super
    end
  end
end
