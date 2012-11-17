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
		
		syscmd("#{Settings::RDIFF_BACKUP} --exclude-globbing-filelist #{f.path}  #{mountpoint} #{Settings::BACKUPER_DEST}/#{@veid}")
		
		db.prepared("DELETE FROM vps_backups WHERE vps_id = ?", @veid)
		
		Dir.glob("#{Settings::BACKUPER_DEST}/#{@veid}/rdiff-backup-data/increments.*.dir").each do |i|
			db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?)", @veid, i.match(/increments\.([^\.]+)\.dir/)[1])
		end
		
		Dir.glob("#{Settings::BACKUPER_DEST}/#{@veid}/rdiff-backup-data/current_mirror.*.data").each do |i|
			db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?)", @veid, i.match(/current_mirror\.([^\.]+)\.data/)[1])
		end
		
		db.close
		
		{:ret => :ok}
	end
	
	def download
		Backuper.wait_for_lock(Db.new, @veid)
		
		syscmd("#{Settings::MKDIR} -p #{Settings::BACKUPER_DOWNLOAD}/#{@params["secret"]}")
		
		if @params["server_name"]
			syscmd("#{Settings::TAR} -czf #{Settings::BACKUPER_DOWNLOAD}/#{@params["secret"]}/#{@params["filename"]} #{mountpoint}")
		else
			syscmd("#{Settings::RDIFF_BACKUP} -r #{@params["datetime"]} #{Settings::BACKUPER_DEST}/#{@veid} #{Settings::BACKUPER_TMP_RESTORE}/#{@veid}")
			syscmd("#{Settings::TAR} -czf #{Settings::BACKUPER_DOWNLOAD}/#{@params["secret"]}/#{@params["filename"]} #{Settings::BACKUPER_TMP_RESTORE}/#{@veid}")
			syscmd("#{Settings::RM} -rf #{Settings::BACKUPER_TMP_RESTORE}/#{@veid}")
		end
	end
	
	def mountpoint
		"#{Settings::BACKUPER_MOUNTPOINT}/#{@params["server_name"]}.#{Settings::DOMAIN}/#{@veid}"
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
			
			sleep(Settings::BACKUPER_LOCK_INTERVAL)
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
