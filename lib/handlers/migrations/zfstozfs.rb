require 'lib/handlers/migration'

module MigrationBackend
	class ZfsToZfsMigration < Migration
		def migrate_part1
			copy_configs
			create_root
			
			zfs(:create, nil, @vps.ve_private_ds)
			# FIXME: zfs send & receive
		end
		
		def migrate_part2
			# FIXME: zfs send & receive
			
			super
		end
	end
end
