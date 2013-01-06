require 'lib/executor'

class Backuper < Executor
	def self.new(*args)
		BackuperBackend.const_get($APP_CONFIG[:backuper][:method]).new(*args)
	end
	
	def backup
		raise CommandNotImplemented
	end
	
	def download
		raise CommandNotImplemented
	end
	
	def mountpoint
		"#{$APP_CONFIG[:backuper][:mountpoint]}/#{@params["server_name"]}.#{$APP_CONFIG[:vpsadmin][:domain]}/#{@veid}"
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
			
			sleep($APP_CONFIG[:backuper][:lock_interval])
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
