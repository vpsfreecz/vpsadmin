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
				
				clear_backups(true)
				update_backups(db)
			end
			
			db.close
			ok
		end
		
		# Make VPS snapshot and enqueue VPS backup, run on vz node
		# 
		# Params:
		# [backuper]  number; ID of backuper
		# [dataset]   string; backup to this dataset
		# [path]      string; backup is in this path
		def backup_snapshot
			vps = ZfsVPS.new(@veid)
			time = "backup-" + Time.new.strftime("%Y-%m-%dT%H:%M:%S")
			
			snapshots = list_snapshots(vps.ve_private_ds)
			oldest_snapshot = snapshots.first
			
			vps.snapshot(vps.ve_private_ds, time)
			
			t = Transaction.new
			t_id = t.queue({
				:node => @params["backuper"],
				:vps => @veid,
				:type => :backup, # FIXME: can be regular on on-demand
				:depends => @command.id,
				:param => {
					:src_node_type => @params["src_node_type"],
					:dst_node_type => @params["dst_node_type"],
					:node_addr => $CFG.get(:vpsadmin, :node_addr),
					:dataset => @params["dataset"],
					:path => @params["path"],
					:snapshot1 => oldest_snapshot ? oldest_snapshot.split("@")[1] : nil,
					:snapshot2 => time,
				},
				
			})
			
			if oldest_snapshot
				t.queue({
					:node => $CFG.get(:vpsadmin, :server_id),
					:vps => @veid,
					:type => :rotate_snapshots,
					:depends => t_id,
				})
			end
			
			ok
		end
		
		def restore_prepare
			target = $CFG.get(:backuper, :restore_target) \
				.gsub(/%\{node\}/, @params["server_name"] + "." + $CFG.get(:vpsadmin, :domain)) \
				.gsub(/%\{veid\}/, @veid)
			syscmd("#{$CFG.get(:bin, :rm)} -rf #{target}") if File.exists?(target)
			
			acquire_lock(Db.new) do
				syscmd("#{$CFG.get(:bin, :rsync)} -rlptgoDH --numeric-ids --inplace --delete-after --exclude .zfs/ #{@params["path"]}/.zfs/snapshot/#{@params["datetime"]}/ #{target}")
			end
			
			ok
		end
	end
end
