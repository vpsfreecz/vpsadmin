require 'lib/handlers/backuper'
require 'lib/utils/zfs'

module BackuperBackend
	class ZfsBackuperCommon < Backuper
		include ::ZfsUtils
		
		
		# Moves current backups to 'trash'
		#
		# Params:
		# [dataset]  string; name of dataset
		def replace_backups
			trash = "#{$CFG.get(:backuper, :zfs, :trash, :dataset)}"
			index = -1
			
			zfs(:list, "-r -d 1 -H -o name", trash)[:output].split().each do |ds|
				m = nil
				
				if (m = ds.match(/#{trash}\/#{@veid}\.(\d+)/))
					i = m[1].to_i
					
					index = i if i > index
				end
			end
			
			zfs(:rename, nil, "#{@params["dataset"]} #{trash}/#{@veid}.#{index+1}")
			zfs(:create, nil, @params["dataset"])
			
			db = Db.new
			update_backups(db)
			db.close
			
			ok
		end
		
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
				name = snapshot.split("@")[1]
				
				if name.start_with?("backup-")
					name = name[7..-1]
				elsif name.start_with?("restore-")
					name = name[8..-1].split(".")[0]
				end
				
				t = Time.parse(name)
				
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
				name = snapshot.split("@")[1]
				
				next if name.start_with?("restore-")
				
				refer = zfs(:get, "-p -H -o value referenced", snapshot)[:output].to_i
				
				if name.start_with?("backup-")
					name = name[7..-1]
				end
				
				db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?), size = ?", @veid, name, refer)
			end
		end
		
		def delete_snapshot(snapshot)
			zfs(:destroy, nil, snapshot)
		end
	end
end
