require 'lib/executor'

# Offline migration abstraction
#
# This class currently supports only offline migration.
# 
# Steps needed to migrate VPS:
# 
# 1. Src: Stop VPS if desired
# 2. Dst: Copy config
# 3. Dst: Sync private
# 4. Src: Stop
# 5. Dst: Sync private
# 6. Dst: Start
# 7. Dst: Relocate in DB
# 8. Src: Destroy
#
# Transaction order (dependencies in brackets):
# 1. Src: Prepare migration
# 2. Dst: Migrate part 1
# 3. Src: Stop (2)
# 4. Dst: Migrate part 2 (3)
# 5. Dst: Apply configs (4)
# 6. Src: Cleanup (4)

class Migration < Executor
	class << self
		alias_method :new_orig, :new
		
		def new(*args)
			src = args[1]["src_node_type"].to_sym
			dst = args[1]["dst_node_type"].to_sym
			
			klass = nil
			
			if src == :ext4 && dst == :ext4
				klass = :ExtToExtMigration
				
			elsif src == :ext4 && dst == :zfs
				klass = :ExtToZfsMigration
				
			elsif src == :zfs && dst == :ext4
				klass = :ZfsToExtMigration
				
			else
				klass = :ZfsToZfsMigration
			end
			
			MigrationBackend.const_get(klass).new_orig(*args)
		end
	end
	
	def initialize(*args)
		super
		
		@vps = VPS.new(@veid)
	end
	
	# Prepare for migration, run on source vz node
	#
	# Params:
	# [stop]: bool; stop VPS before migration?
	def prepare
		@vps.stop if @params["stop"]
		ok
	end
	
	# Sync private when src VPS is running, run on destination vz node
	#
	# Params:
	# [src_node_type]  string; ext or zfs
	# [dst_node_type]  string; ext or zfs
	# [src_addr]       string; IP address of source node
	# [src_ve_private] string; Path to VE private on source node
	def migrate_part1
		copy_configs
		create_root
		sync_private
	end
	
	# Resync private when src VPS is stopped, run on destination vz node
	#
	# Params:
	# [src_node_type]  string; ext or zfs
	# [dst_node_type]  string; ext or zfs
	# [src_addr]       string; IP address of source node
	# [src_ve_private] string; Path to VE private on source node
	# [start]          bool; start VPS after migration?
	def migrate_part2
		@vps.start if @params["start"]
		
		@relocate = true
		ok
	end
	
	# Post-migration actions, run on source vz node
	def cleanup
		@vps.destroy
	end
	
	def copy_configs
		scp("#{@params["src_addr"]}:#{$CFG.get(:vz, :vz_conf)}/conf/#{@veid}.*", "#{$CFG.get(:vz, :vz_conf)}/conf/")
	end
	
	def create_root
		path = "#{$CFG.get(:vz, :vz_root)}/root/#{@veid}"
		
		if File.exists?(path)
			begin
				Dir.rmdir(path)
			rescue SystemCallError => err
				raise CommandFailed.new("rmdir", 1, err.to_s)
			end
		end
		
		syscmd("#{$CFG.get(:bin, :mkdir)} #{path}")
	end
	
	def sync_private
		syscmd($CFG.get(:vps, :migration, :rsync) \
			.gsub(/%\{rsync\}/, $CFG.get(:bin, :rsync)) \
			.gsub(/%\{src\}/, "#{@params["src_addr"]}:#{@params["src_ve_private"]}/") \
			.gsub(/%\{dst\}/, @vps.ve_private))
	end
	
	def post_save(db)
		if @relocate
			db.prepared("UPDATE vps SET vps_server = ? WHERE vps_id = ?", $CFG.get(:vpsadmin, :server_id), @veid)
			@vps.update_status(db)
		end
	end
end

require 'lib/handlers/migrations/exttoext'
require 'lib/handlers/migrations/exttozfs'
require 'lib/handlers/migrations/zfstoext'
require 'lib/handlers/migrations/zfstozfs'
