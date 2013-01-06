require 'lib/handlers/backuper'

require 'tempfile'

module BackuperBackend
	class Zfs < BackuperInterface
		def backup
			db = Db.new
			
			Backuper.wait_for_lock(db, @veid)
			
			f = Tempfile.new("backuper_exclude")
			@params["exclude"].each do |s|
				f.puts(File.join(mountpoint, s))
			end
			f.close
			
			syscmd("#{$APP_CONFIG[:bin][:zfs]} create -p #{$APP_CONFIG[:backuper][:zfs][:zpool]}/#{@veid}")
			syscmd("#{$APP_CONFIG[:bin][:rsync]} -rlptgoDHX --numeric-ids --inplace --delete-after --exclude-from #{f.path} #{mountpoint}/ #{$APP_CONFIG[:backuper][:dest]}/#{@veid}/")
			syscmd("#{$APP_CONFIG[:bin][:zfs]} snapshot #{$APP_CONFIG[:backuper][:zfs][:zpool]}/#{@veid}@#{Time.new.strftime("%Y-%m-%dT%H:%M:%S")}")
			
			db.prepared("DELETE FROM vps_backups WHERE vps_id = ?", @veid)
			
			syscmd("#{$APP_CONFIG[:bin][:zfs]} list -r -t snapshot -H -o name #{$APP_CONFIG[:backuper][:zfs][:zpool]}/#{@veid}")[:output].split('\n').each do |snapshot|
				db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?)", @veid, snapshot)
			end
			
			db.close
			
			ok
		end
	end
end
