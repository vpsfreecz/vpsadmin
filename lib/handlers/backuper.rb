require 'lib/executor'

class Backuper < Executor
	class << self
		alias_method :new_orig, :new
		
		def new(*args)
			BackuperBackend.const_get($CFG.get(:backuper, :method)).new_orig(*args)
		end
	end
	
	def backup
		raise CommandNotImplemented
	end
	
	def download
		raise CommandNotImplemented
	end
	
	def restore_prepare
		raise CommandNotImplemented
	end
	
	def restore_finish
		target = $CFG.get(:backuper, :restore_src).gsub(/%\{veid\}/, @veid)
		
		vps = VPS.new(@veid)
		
		vps.stop(:force => true)
		syscmd("#{$CFG.get(:vz, :vzquota)} off #{@veid} -f", [6,])
		vps.stop
		
		acquire_lock(Db.new) do
			syscmd("#{$CFG.get(:bin, :rm)} -rf #{$CFG.get(:vz, :vz_root)}/private/#{@veid}")
			syscmd("#{$CFG.get(:bin, :mv)} #{target} #{$CFG.get(:vz, :vz_root)}/private/#{@veid}")
		end
		
		syscmd("#{$CFG.get(:vz, :vzquota)} drop #{@veid}")
		vps.start
	end
	
	def exports
		raise CommandFailed("exports", 1, "Exports disabled in configuration") unless $CFG.get(:backuper, :exports, :enabled)
		
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
	
	def write_exports(f, dest)
		options = $CFG.get(:backuper, :exports, :options)
		
		Dir.entries(dest).each do |d|
			next if d == "." || d == ".."
			
			options.each do |o|
				f.puts("#{dest}/#{d} #{o}")
			end
		end
	end
	
	def mountdir
		"#{$CFG.get(:backuper, :mountpoint)}/#{@params["server_name"]}.#{$CFG.get(:vpsadmin, :domain)}"
	end
	
	def mountpoint
		"#{mountdir}/#{@veid}"
	end
	
	def acquire_lock(db)
		set_step("[waiting for lock]")
		
		Backuper.wait_for_lock(db, @veid) do
			yield
		end
	end
	
	def post_save(db)
		Backuper.unlock(db, @veid)
	end
	
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
	
	def Backuper.unlock(db, veid)
		db.prepared("UPDATE vps SET vps_backup_lock = 0 WHERE vps_id = ?", veid)
	end
end

require 'lib/handlers/backupers/rdiffbackup'
require 'lib/handlers/backupers/zfs'
