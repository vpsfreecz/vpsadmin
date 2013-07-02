require 'lib/handlers/backupers/zfs/common'
require 'lib/utils/zfs'

require 'fileutils'
require 'tempfile'

module BackuperBackend
	class ExtToZfs < ZfsBackuperCommon
		def backup
			db = Db.new
			
			acquire_lock(db) do
				@exclude = Tempfile.new("backuper_exclude")
				@params["exclude"].each do |s|
					@exclude.puts(s)
				end
				@exclude.close
				
				unless File.exists?(@params["path"])
					zfs(:create, nil, @params["dataset"])
				end
				
				syscmd(rsync, [23, 24])
				zfs(:snapshot, nil, "#{@params["dataset"]}@#{Time.new.strftime("%Y-%m-%dT%H:%M:%S")}")
				
				clear_backups(true)
				update_backups(db)
			end
			
			db.close
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
		
		def rsync
			$CFG.get(:backuper, :zfs, :rsync) \
				.gsub(/%\{rsync\}/, $CFG.get(:bin, :rsync)) \
				.gsub(/%\{exclude\}/, @exclude.path) \
				.gsub(/%\{src\}/, mountpoint + "/") \
				.gsub(/%\{dst\}/, @params["path"])
		end
	end
end
