require 'lib/handlers/backupers/zfs/common'
require 'lib/utils/zfs'

require 'fileutils'
require 'tempfile'

module BackuperBackend
	class ZfsToZfs < ZfsBackuperCommon
		def backup
			db = Db.new
			
			acquire_lock(db) do
				unless File.exists?(@params["path"])
					zfs(:create, nil, @params["dataset"])
				end
				
				recv = "zfs recv -F #{@params["dataset"]}"
				
				# FIXME: remove hardcoded path
				if @params["snapshot1"]
					send = "zfs send -I vz/private/#{@veid}@#{@params["snapshot1"]} vz/private/#{@veid}@#{@params["snapshot2"]}"
				else
					send = "zfs send vz/private/#{@veid}@#{@params["snapshot2"]}"
				end
				
				syscmd("ssh #{@params["node_addr"]} #{send} | #{recv}")
				
				clear_backups(true) if @params["rotate_backups"]
				update_backups(db)
			end
			
			db.close
			ok
		end
		
		# Make VPS snapshot and enqueue VPS backup, run on vz node
		# 
		# Params:
		# [backuper]        number; ID of backuper
		# [dataset]         string; backup to this dataset
		# [path]            string; backup is in this path
		# [backup_type]     number; transaction type ID, regular or on-demand backup
		# [set_dependency]  number, optional; the ID of transaction that should depend on the backup
		def backup_snapshot
			vps = ZfsVPS.new(@veid)
			time = "backup-" + Time.new.strftime("%Y-%m-%dT%H:%M:%S")
			
			snapshots = list_snapshots(vps.ve_private_ds)
			oldest_snapshot = snapshots.first
			
			vps.snapshot(vps.ve_private_ds, time)
			
			db = Db.new
			
			t = Transaction.new(db)
			t_id = t.queue({
				:node => @params["backuper"],
				:vps => @veid,
				:type => @params["backup_type"] == 5005 ? :backup_schedule : :backup_regular,
				:depends => @command.id,
				:param => {
					:src_node_type => @params["src_node_type"],
					:dst_node_type => @params["dst_node_type"],
					:node_addr => $CFG.get(:vpsadmin, :node_addr),
					:dataset => @params["dataset"],
					:path => @params["path"],
					:snapshot1 => oldest_snapshot ? oldest_snapshot.split("@")[1] : nil,
					:snapshot2 => time,
					:rotate_backups => @params["rotate_backups"],
				},
				
			})
			
			if oldest_snapshot
				t_id = t.queue({
					:node => $CFG.get(:vpsadmin, :server_id),
					:vps => @veid,
					:type => :rotate_snapshots,
					:depends => t_id,
				})
			end
			
			if @params["set_dependency"]
				db.prepared("UPDATE transactions SET t_depends_on = ? WHERE t_id = ?", t_id, @params["set_dependency"])
			end
			
			db.close
			
			ok
		end
		
		def restore_prepare
			ds = "#{ZfsVPS.new(@veid).ve_private_ds}.restoring"
			
			begin
				zfs(:get, "name", ds)
				zfs(:destroy, "-r", ds)
			
			rescue CommandFailed => e
				raise e if e.rc != 1
				
			ensure
				zfs(:create, nil, ds)
			end
			
			ok
		end
		
		def restore_restore
			restore_ds = "#{$CFG.get(:backuper, :restore, :zfs, :dataset)}/#{@veid}"
			
			# This code does not count with older snapshot naming without backup- prefix
			zfs(:clone, nil, "#{@params["dataset"]}@backup-#{@params["datetime"]} #{restore_ds}")
			
			rsync([:backuper, :restore, :zfs, :head_rsync], {
				:src => "/#{restore_ds}/",
				:dst => @params["path"],
			})
			
			zfs(:destroy, "-r", restore_ds)
			
			index = -1
			
			list_snapshots(@params["dataset"]).each do |sn|
				m = nil
				
				if (m = sn.match(/#{@params["dataset"]}@restore-\d+-\d+-\d+T\d+\:\d+\:\d+\.(\d+)/))
					i = m[1].to_i
					
					index = i if i > index
				end
			end
			
			snapshot = "#{@params["dataset"]}@restore-#{@params["datetime"]}.#{index+1}"
			zfs(:snapshot, nil, snapshot)
			
			send = "zfs send #{snapshot}"
			recv = "zfs recv -F #{ZfsVPS.new(@veid).ve_private_ds}.restoring"
			
			syscmd("#{send} | ssh #{@params["node_addr"]} #{recv}")
		end
		
		def restore_finish
			vps = ZfsVPS.new(@veid)
			tmp = "#{vps.ve_private_ds}.restoring"
			
			vps.honor_state do
				vps.stop
				
				acquire_lock(Db.new) do
					zfs(:set, "quota=#{zfs(:get, "-H -ovalue quota", vps.ve_private_ds)[:output].strip}", tmp)
					zfs(:destroy, "-r", vps.ve_private_ds)
					zfs(:rename, nil, "#{tmp} #{vps.ve_private_ds}")
					
					zfs(:mount, nil, vps.ve_private_ds, [1,]) # FIXME: why is it unmounted?
				end
			end
		end
	end
end
