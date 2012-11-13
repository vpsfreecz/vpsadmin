require 'lib/executor'

require 'tempfile'

class Backuper < Executor
	def backup
		db = Db.new
		
		loop do
			if (st = db.prepared_st("UPDATE vps SET vps_backup_lock = 1 WHERE vps_id = ? AND vps_backup_lock = 0", @veid)).affected_rows == 1
				break
			end
			
			st.close
			
			sleep(Settings::BACKUPER_LOCK_INTERVAL)
		end
		
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
	
	def mountpoint
		"#{Settings::BACKUPER_MOUNTPOINT}/#{@params["server_name"]}.#{Settings::DOMAIN}/#{@veid}"
	end
	
	def post_save(db)
		db.prepared("UPDATE vps SET vps_backup_lock = 0 WHERE vps_id = ?", @veid)
	end
	
	def backup_all
		backups = []
		db = Db.new
		
		# FIXME: select only vpses whose servers are in location that has set this backup server
		rs = db.query("SELECT server_name, vps_id
		              FROM vps v INNER JOIN servers s ON v.vps_server = s.server_id")
		
		db.close
		
		rs.each do |row|
			while backups.count == Settings::BACKUPER_CONCURRENCY
				backups.delete_if do |t|
					not t.alive?
				end
				
				sleep(60) if backups.count == Settings::BACKUPER_CONCURRENCY
			end
			
			backups << Thread.new do
				backup(:veid => row["vps_id"], :server_name => row["server_name"])
			end
		end
		
		backups.each do |t|
			t.join
		end
	end
end
