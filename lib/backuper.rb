require 'lib/executor'

require 'tempfile'

class Backuper < Executor
	def backup
		db = Db.new
		
		Backuper.wait_for_lock(db, @veid)
		
		f = Tempfile.new("backuper_exclude")
		@params["exclude"].each do |s|
			f.puts(File.join(mountpoint, s))
		end
		f.close
		
		syscmd("#{$APP_CONFIG[:bin][:rdiff_backup]} --exclude-globbing-filelist #{f.path}  #{mountpoint} #{$APP_CONFIG[:backuper][:dest]}/#{@veid}")
		
		db.prepared("DELETE FROM vps_backups WHERE vps_id = ?", @veid)
		
		Dir.glob("#{$APP_CONFIG[:backuper][:dest]}/#{@veid}/rdiff-backup-data/increments.*.dir").each do |i|
			db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?)", @veid, i.match(/increments\.([^\.]+)\.dir/)[1])
		end
		
		Dir.glob("#{$APP_CONFIG[:backuper][:dest]}/#{@veid}/rdiff-backup-data/current_mirror.*.data").each do |i|
			db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?)", @veid, i.match(/current_mirror\.([^\.]+)\.data/)[1])
		end
		
		db.close
		
		ok
	end
	
	def download
		Backuper.wait_for_lock(Db.new, @veid)
		
		syscmd("#{$APP_CONFIG[:bin][:mkdir]} -p #{$APP_CONFIG[:backuper][:download]}/#{@params["secret"]}")
		
		if @params["server_name"]
			syscmd("#{$APP_CONFIG[:bin][:tar]} -czf #{$APP_CONFIG[:backuper][:download]}/#{@params["secret"]}/#{@params["filename"]} #{mountpoint}")
		else
			syscmd("#{$APP_CONFIG[:bin][:rdiff_backup]} -r #{@params["datetime"]} #{$APP_CONFIG[:backuper][:dest]}/#{@veid} #{$APP_CONFIG[:backuper][:tmp_restore]}/#{@veid}")
			syscmd("#{$APP_CONFIG[:bin][:tar]} -czf #{$APP_CONFIG[:backuper][:download]}/#{@params["secret"]}/#{@params["filename"]} #{$APP_CONFIG[:backuper][:tmp_restore]}/#{@veid}")
			syscmd("#{$APP_CONFIG[:bin][:rm]} -rf #{$APP_CONFIG[:backuper][:tmp_restore]}/#{@veid}")
		end
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
