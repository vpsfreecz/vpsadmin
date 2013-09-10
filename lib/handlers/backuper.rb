require 'lib/executor'

# Handles backups on storage node
#
# The naming of specific implementations has the following format:
#   <node>To<backuper>, eg. ExtToZfs
# even if the order of operation is opposite.
class Backuper < Executor
	class << self
		alias_method :new_orig, :new
		
		def new(*args)
			klass = nil
			
			begin
				src = args[1]["src_node_type"].to_sym
				dst = args[1]["dst_node_type"].to_sym
				
				if src == :ext4 && dst == :zfs
					klass = :ExtToZfs
					
				elsif src == :zfs && dst == :zfs
					klass = :ZfsToZfs
					
				elsif src == :zfs_compat && dst == :zfs
					klass = :ZfsCompatToZfs
					
				else
					raise CommandFailed.new("Backuper.new", 1, "Unsupported backup type #{src} to #{dst}")
				end
			
			rescue NoMethodError
				klass = :ZfsBackuperCommon
			end
			
			BackuperBackend.const_get(klass).new_orig(*args)
		end
	end
	
	# Backup VPS
	#
	# Params:
	# [src_node_type]   string; ext4 or zfs
	# [dst_node_type]   string; ext4 or zfs
	# [exclude]         list; paths to be excluded from backup
	# [server_name]     string; name of server VPS runs on
	# [node_addr]   string; IP address of server VPS runs on
	# [dataset]         string; backup to this dataset
	# [path]            string; backup is in this path
	# [rotate_backups]  bool; rotate backups?
	def backup
		raise CommandNotImplemented
	end
	
	# Delete old backups
	#
	# [dataset]     string; backup to this dataset
	# [path]        string; backup is in this path
	def clear_backups(locked = false)
		raise CommandNotImplemented
	end
	
	# Prepare archive of selected VPS backup or its current state
	#
	# Params:
	# [secret]      string; secret key, used as name of directory
	# [filename]    string; full name of archive
	# [datetime]    string, date format %Y-%m-%dT%H:%M:%S; download backup from this date
	# [server_name] string; if specified, do not download backup but VPS current state from node with this name
	# [node_addr]   string; IP address of server VPS runs on
	# [dataset]     string; backup to this dataset
	# [path]        string; backup is in this path
	def download
		raise CommandNotImplemented
	end
	
	# First part of restore, run on vz node
	# [src_node_type]  string; ext4 or zfs
	# [dst_node_type]  string; ext4 or zfs
	def restore_prepare
		raise CommandNotImplemented
	end
	
	# Copy data from backuper to vz node, run on backuper
	#
	# Params:
	# [src_node_type]  string; ext4 or zfs
	# [dst_node_type]  string; ext4 or zfs
	# [datetime]    string, date format %Y-%m-%dT%H:%M:%S; restore from backup from this date
	# [backuper]    string; name of backuper server
	# [server_name] string; name of server VPS runs on
	# [node_addr]   string; IP address of server VPS runs on
	# [dataset]     string; backup to this dataset
	# [path]        string; backup is in this path
	def restore_restore
		raise CommandNotImplemented
	end
	
	# Final part of restore, run on vz node
	#
	# Parameters same as for #restore_restore.
	def restore_finish
		target = $CFG.get(:backuper, :restore_src).gsub(/%\{veid\}/, @veid)
		
		vps = VPS.new(@veid)
		
		vps.honor_state do
			vps.stop(:force => true)
			syscmd("#{$CFG.get(:vz, :vzquota)} off #{@veid} -f", [6,])
			vps.stop
			
			acquire_lock(Db.new) do
				syscmd("#{$CFG.get(:bin, :chmod)} -R -t #{$CFG.get(:vz, :vz_root)}/private/#{@veid}")
				syscmd("#{$CFG.get(:bin, :rm)} -rf #{$CFG.get(:vz, :vz_root)}/private/#{@veid}")
				syscmd("#{$CFG.get(:bin, :mv)} #{target} #{$CFG.get(:vz, :vz_root)}/private/#{@veid}")
			end
			
			# Ignore rc 11 - returned when quota does not exist
			syscmd("#{$CFG.get(:vz, :vzquota)} drop #{@veid}", [11,])
		end
	end
	
	# Deprecated, not working
	def exports
		raise CommandFailed.new("exports", 1, "Exports disabled in configuration") unless $CFG.get(:backuper, :exports, :enabled)
		
		delimiter = $CFG.get(:backuper, :exports, :delimiter)
		dest = $CFG.get(:backuper, :dest)
		path = $CFG.get(:backuper, :exports, :path)
		path_new = path + ".new"
		
		src = File.open(path, "r")
		dst = File.open(path_new, "w")
		written = false
		
		while line = src.gets
			dst.write(line)
			
			if line.strip == delimiter
				written = true
				write_exports(dst, dest)
				break
			end
		end
		
		unless written
			dst.puts(delimiter)
			write_exports(dst, dest)
		end
		
		src.close
		dst.close
		
		FileUtils.mv(path_new, path)
		
		syscmd($CFG.get(:backuper, :exports, :reexport))
	end
	
	# Deprecated, not working
	def write_exports(f, dest)
		options = $CFG.get(:backuper, :exports, :options)
		
		Dir.entries(dest).each do |d|
			next if d == "." || d == ".."
			
			options.each do |o|
				f.puts("#{dest}/#{d} #{o}")
			end
		end
	end
	
	def mountdir(node_name = nil)
		"#{$CFG.get(:backuper, :mountpoint)}/#{node_name.nil? ? @params["server_name"] : node_name}.#{$CFG.get(:vpsadmin, :domain)}"
	end
	
	def mountpoint(node_name = nil, veid = nil)
		"#{mountdir(node_name)}/#{veid.nil? ? @veid : veid}"
	end
	
	def backup_snapshot_path
		path = "#{@params["path"]}/.zfs/snapshot/#{@params["datetime"]}"
		
		if File.exists?(path)
			return path
		end
		
		"#{@params["path"]}/.zfs/snapshot/backup-#{@params["datetime"]}"
	end
	
	# Sets appropriate command state, wait for lock, run block and unclock VPS again
	def acquire_lock(db)
		set_step("[waiting for lock]")
		
		Backuper.wait_for_lock(db, @veid) do
			yield
		end
	end
	
	def post_save(db)
		Backuper.unlock(db, @veid)
	end
	
	# Blocks until it locks VPS
	def Backuper.wait_for_lock(db, veid)
		loop do
			if (st = db.prepared_st("UPDATE vps SET vps_backup_lock = 1 WHERE vps_id = ? AND vps_backup_lock = 0", veid)).affected_rows == 1
				break
			end
			
			st.close
			
			sleep($CFG.get(:backuper, :lock_interval))
		end
		
		if block_given?
			yield
			Backuper.unlock(db, veid)
		end
	end
	
	# Unlock VPS
	def Backuper.unlock(db, veid)
		db.prepared("UPDATE vps SET vps_backup_lock = 0 WHERE vps_id = ?", veid)
	end
end

require 'lib/handlers/backupers/rdiffbackup'
require 'lib/handlers/backupers/zfs/exttozfs'
require 'lib/handlers/backupers/zfs/zfstozfs'
require 'lib/handlers/backupers/zfs/zfscompattozfs'
