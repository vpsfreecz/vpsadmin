require 'lib/handlers/backuper'

require 'tempfile'

module BackuperBackend
	class Zfs < Backuper
		def backup
			db = Db.new
			
			Backuper.wait_for_lock(db, @veid)
			
			f = Tempfile.new("backuper_exclude")
			@params["exclude"].each do |s|
				f.puts(File.join(mountpoint, s))
			end
			f.close
			
			syscmd("#{$CFG.get(:bin, :zfs)} create -p #{$CFG.get(:backuper, :zfs)[:zpool]}/#{@veid}")
			syscmd("#{$CFG.get(:bin, :rsync)} -rlptgoDHX --numeric-ids --inplace --delete-after --exclude .zfs/ --exclude-from #{f.path} #{mountpoint}/ #{$CFG.get(:backuper, :dest)}/#{@veid}/", [24,])
			syscmd("#{$CFG.get(:bin, :zfs)} snapshot #{$CFG.get(:backuper, :zfs)[:zpool]}/#{@veid}@#{Time.new.strftime("%Y-%m-%dT%H:%M:%S")}")
			
			db.prepared("DELETE FROM vps_backups WHERE vps_id = ?", @veid)
			
			syscmd("#{$CFG.get(:bin, :zfs)} list -r -t snapshot -H -o name #{$CFG.get(:backuper, :zfs)[:zpool]}/#{@veid}")[:output].split('\n').each do |snapshot|
				db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?)", @veid, snapshot.split("@")[1])
			end
			
			db.close
			
			ok
		end
	end
end
