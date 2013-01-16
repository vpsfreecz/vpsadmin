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
	
	def mountpoint
		"#{$CFG.get(:backuper, :mountpoint)}/#{@params["server_name"]}.#{$CFG.get(:vpsadmin, :domain)}/#{@veid}"
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
