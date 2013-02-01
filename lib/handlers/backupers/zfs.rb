require 'lib/handlers/backuper'

require 'fileutils'
require 'tempfile'

module BackuperBackend
	class Zfs < Backuper
		def backup
			db = Db.new
			
			acquire_lock(db) do
				@exclude = Tempfile.new("backuper_exclude")
				@params["exclude"].each do |s|
					@exclude.puts(s)
				end
				@exclude.close
				
				unless File.exists?("#{$CFG.get(:backuper, :dest)}/#{@veid}")
					syscmd("#{$CFG.get(:bin, :zfs)} create #{$CFG.get(:backuper, :zfs)[:zpool]}/#{@veid}")
					exports if $CFG.get(:backuper, :exports, :enabled)
				end
				
				syscmd(rsync, [23, 24])
				syscmd("#{$CFG.get(:bin, :zfs)} snapshot #{$CFG.get(:backuper, :zfs)[:zpool]}/#{@veid}@#{Time.new.strftime("%Y-%m-%dT%H:%M:%S")}")
				
				db.prepared("DELETE FROM vps_backups WHERE vps_id = ?", @veid)
				
				syscmd("#{$CFG.get(:bin, :zfs)} list -r -t snapshot -H -o name #{$CFG.get(:backuper, :zfs)[:zpool]}/#{@veid}")[:output].split().each do |snapshot|
					db.prepared("INSERT INTO vps_backups SET vps_id = ?, timestamp = UNIX_TIMESTAMP(?)", @veid, snapshot.split("@")[1])
				end
			end
			
			db.close
			ok
		end
		
		def download
			acquire_lock(Db.new) do
				syscmd("#{$CFG.get(:bin, :mkdir)} -p #{$CFG.get(:backuper, :download)}/#{@params["secret"]}")
				
				if @params["server_name"]
					syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} -C #{mountdir} #{@veid}", [1,])
				else
					syscmd("#{$CFG.get(:bin, :tar)} -czf #{$CFG.get(:backuper, :download)}/#{@params["secret"]}/#{@params["filename"]} -C #{$CFG.get(:backuper, :dest)}/#{@veid}/.zfs/snapshot #{@params["datetime"]}")
				end
			end
			
			ok
		end
		
		def restore_prepare
			target = $CFG.get(:backuper, :restore_target) \
				.gsub(/%\{node\}/, @params["server_name"] + "." + $CFG.get(:vpsadmin, :domain)) \
				.gsub(/%\{veid\}/, @veid)
			syscmd("#{$CFG.get(:bin, :rm)} -rf #{target}") if File.exists?(target)
			
			acquire_lock(Db.new) do
				syscmd("#{$CFG.get(:bin, :rsync)} -rlptgoDHX --numeric-ids --inplace --delete-after --exclude .zfs/ #{$CFG.get(:backuper, :dest)}/#{@veid}/.zfs/snapshot/#{@params["datetime"]}/ #{target}")
			end
			
			ok
		end
		
		def rsync
			$CFG.get(:backuper, :zfs, :rsync) \
				.gsub(/%\{rsync\}/, $CFG.get(:bin, :rsync)) \
				.gsub(/%\{exclude\}/, @exclude.path) \
				.gsub(/%\{src\}/, mountpoint + "/") \
				.gsub(/%\{dst\}/, "#{$CFG.get(:backuper, :dest)}/#{@veid}/")
		end
	end
end
