require 'lib/handlers/migration'
require 'lib/utils/zfs'

module MigrationBackend
	class ExtToZfsMigration < Migration
		include ZfsUtils
		
		def migrate_part1
			copy_configs
			create_root
			
			zfs(:create, nil, @vps.ve_private_ds)
			sync_private
		end
		
		def migrate_part2
			sync_private
			
			vzctl(:set, @veid, {:root => @vps.ve_root, :private => @vps.ve_private}, true)
			
			super
		end
	end
end
