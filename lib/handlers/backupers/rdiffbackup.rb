require 'lib/handlers/backuper'

require 'tempfile'

module BackuperBackend
	class RdiffBackup < Backuper
		def backup
			db = Db.new
			
			Backuper.wait_for_lock(db, @veid)
			
			f = Tempfile.new("backuper_exclude")
			@params["exclude"].each do |s|
				f.puts(File.join(mountpoint, s))
			end
			f.close
			
			syscmd("#{$CFG.get(:bin, :rdiff_backup)} --exclude-globbing-filelist #{f.path}  #{mountpoint} #{$CFG.get(:backuper, :dest)}/#{@veid}")
			
			db.prepared("DELETE FROM vps_backups WHERE vps_id = ?", @veid)
			
			Dir.glob("#{$CFG.get(:backuper, :dest)}/#{@veid}/rdiff-backup-data/increments.*.dir").each do |i|
				db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?)", @veid, i.match(/increments\.([^\.]+)\.dir/)[1])
			end
			
			Dir.glob("#{$CFG.get(:backuper, :dest)}/#{@veid}/rdiff-backup-data/current_mirror.*.data").each do |i|
				db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?)", @veid, i.match(/current_mirror\.([^\.]+)\.data/)[1])
			end
			
			db.close
			
			ok
		end
		
		def download
			Backuper.wait_for_lock(Db.new, @veid)
			
			syscmd("#{$CFG.get(:bin, :mkdir)} -p #{$CFG.get(:backuper, :download)}/#{@params["secret"]}")
			
			if @params["server_name"]
				syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} #{mountpoint}", [1,])
			else
				syscmd("#{$CFG.get(:bin, :rdiff_backup)} -r #{@params["datetime"]} #{$CFG.get(:backuper, :dest)}/#{@veid} #{$CFG.get(:backuper, :tmp_restore)}/#{@veid}")
				syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} #{$CFG.get(:backuper, :tmp_restore)}/#{@veid}")
				syscmd("#{$CFG.get(:bin, :rm)} -rf #{$CFG.get(:backuper, :tmp_restore)}/#{@veid}")
			end
		end
	end
end
