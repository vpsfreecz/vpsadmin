require 'lib/handlers/backuper'
require 'lib/utils/zfs'

module BackuperBackend
	class ZfsBackuperCommon < Backuper
		include ::ZfsUtils
		
		def clear_backups(locked = false)
			unless locked
				Backuper.wait_for_lock(Db.new, @veid)
			end
			
			snapshots = zfs(:list, "-r -t snapshot -H -o name", @params["dataset"])[:output].split()

			deleted = 0
			min_backups = $CFG.get(:backuper, :store, :min_backups)
			max_backups = $CFG.get(:backuper, :store, :max_backups)
			oldest_backup = Time.new - $CFG.get(:backuper, :store, :max_age) * 24 * 60 * 60
			
			if snapshots.count <= min_backups
				return # Nothing to delete
			end
			
			snapshots.each do |snapshot|
				t = Time.parse(snapshot.split("@")[1])
				
				if (t < oldest_backup && (snapshots.count - deleted) > min_backups) or ((snapshots.count - deleted) > max_backups)
					deleted += 1
					delete_snapshot(snapshot)
				end
				
				if snapshots.count <= min_backups or (t > oldest_backup && (snapshots.count - deleted) <= max_backups)
					break
				end
			end
			
			ok
		end
		
		def update_backups(db)
			db.prepared("DELETE FROM vps_backups WHERE vps_id = ?", @veid)
			
			list_snapshots(@params["dataset"]).each do |snapshot|
				refer = zfs(:get, "-p -H -o value referenced", snapshot)[:output].to_i
				name = snapshot.split("@")[1]
				
				if name.starts_with?("backup-")
					name = name[7..-1]
				end
				
				db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?), size = ?", @veid, name, refer)
			end
		end
		
		def delete_snapshot(snapshot)
				zfs(:destroy, nil, snapshot)
			end
		
		def download
			acquire_lock(Db.new) do
				syscmd("#{$CFG.get(:bin, :mkdir)} -p #{$CFG.get(:backuper, :download)}/#{@params["secret"]}")
				
				if @params["server_name"]
					syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} -C #{mountdir} #{@veid}", [1,])
				else
					syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} -C #{@params["path"]}/.zfs/snapshot #{@params["datetime"]}")
				end
			end
			
			ok
		end
	end
end
