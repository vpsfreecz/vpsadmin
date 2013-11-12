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
		
		def download
			acquire_lock(Db.new) do
				syscmd("#{$CFG.get(:bin, :mkdir)} -p #{$CFG.get(:backuper, :download)}/#{@params["secret"]}")
				
				if @params["server_name"]
					mount_vps do
						syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} -C #{mountdir} #{@veid}", [1,])
					end
				else
					syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} -C #{@params["path"]}/.zfs/snapshot backup-#{@params["datetime"]}")
				end
			end
			
			ok
		end
		
		def mount_all
			
		end
		
		def mount_vps(node_addr = nil, node_name = nil, veid = nil)
			node_addr ||= @params["node_addr"]
			node_name ||= @params["server_name"]
			veid ||= @veid
			
			m = mountpoint(node_name, veid)
			
			Dir.mkdir(m) unless File.exists?(m)
			
			begin
				syscmd("#{$CFG.get(:bin, :mount)} -overs=3 #{node_addr}:/vz/private/#{veid} #{m}")
			rescue CommandFailed => err
				raise err if err.rc != 33
			end
			
			if block_given?
				yield
				
				syscmd("#{$CFG.get(:bin, :umount)} -f #{m}")
				Dir.rmdir(m)
			end
			
			ok
		end
	end
end
