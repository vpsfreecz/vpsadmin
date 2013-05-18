require 'lib/handlers/storage'
require 'lib/utils/zfs'

module StorageBackend
	# Storage implementation using ZFS
	class Zfs < Storage
		include ZfsUtils
		
		# Create export
		# 
		# Params:
		# [dataset]       string; name of dataset
		# [path]          string; mountpoint path
		# [export_id]     number; id of export
		# [share_options] string, optional; passed directly to zfs sharenfs
		# [quota]         number; quota for this export, in bytes
		def create_export
			if File.directory?(@params["path"])
				@delete_export = @params["export_id"]
				raise CommandFailed.new("create_export", 1, "Mountpoint already exists, cannot continue")
			end
			
			zfs(:create, "-p", @params["dataset"])
			update_export
		end
		
		# Update export
		# 
		# Params:
		# [dataset]       string; name of dataset
		# [share_options] string, optional; passed directly to zfs sharenfs
		# [quota]         number; quota for this export, in bytes
		def update_export
			zfs(:set, "sharenfs=\"#{@params["share_options"]}\"", @params["dataset"]) if @params["share_options"]
			zfs(:set, "quota=#{@params["quota"].to_i == 0 ? "none" : @params["quota"]}", @params["dataset"])
		end
		
		# Delete export
		#
		# Params:
		# [path]      string; name of dataset
		# [recursive] bool; if true then delete all descendants
		def delete_export
			zfs(:destroy, @params["recursive"] ? "-r" : nil, @params["path"])
		end
		
		def post_save(db)
			if @delete_export
				db.prepared("DELETE FROM storage_export WHERE id = ?", @delete_export)
			end
		end
		
		def update_status
			db = Db.new
			list_exports(db).each_hash do |e|
				quota = used = avail = 0
				
				get = zfs(:get, "-H -p -o property,value quota,used,available", "#{e["root_dataset"]}/#{e["dataset"]}", [1,])
				
				next if get[:exitstatus] == 1
				
				get[:output].split("\n").each do |prop|
					p = prop.split
					
					case p[0]
					when "quota" then
						quota = p[1]
					when "used" then
						used = p[1]
					when "available" then
						avail = p[1]
					end
				end
				
				db.prepared(
					"UPDATE storage_export SET quota = ?, used = ?, avail = ? WHERE id = ?",
					quota, used, avail, e["id"].to_i
				)
			end
		end
	end
end
