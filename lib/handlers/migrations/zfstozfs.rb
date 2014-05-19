require 'lib/handlers/migration'

module MigrationBackend
  class ZfsToZfsMigration < Migration
    include ::ZfsUtils

    def prepare
      @vps.stop if @params['stop']
      zfs(:snapshot, nil, "#{@vps.ve_private_ds}@emergency-migration-p1")
      ok
    end

    def migrate_part1
      copy_configs
      create_root

      zfs(:create, '-p', @vps.ve_private_ds)
      syscmd("ssh #{@params['src_addr']} zfs send #{@vps.ve_private_ds}@emergency-migration-p1 | zfs recv -F #{@vps.ve_private_ds}")
    end

    def migrate_part2
      syscmd("ssh #{@params['src_addr']} zfs snapshot #{@vps.ve_private_ds}@emergency-migration-p2")
      syscmd("ssh #{@params['src_addr']} zfs send -i #{@vps.ve_private_ds}@emergency-migration-p1 #{@vps.ve_private_ds}@emergency-migration-p2 | zfs recv -F #{@vps.ve_private_ds}")

      super
    end
  end
end
