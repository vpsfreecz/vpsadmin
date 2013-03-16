require 'lib/handlers/storage'
require 'lib/utils/zfs'

module StorageBackend
	# Storage implementation using ZFS
	class Zfs < Storage
		include ZfsUtils
		
		# Create export
		# 
		# Params:
		# [path]          string; name of dataset
		# [share_options] string, optional; passed directly to zfs sharenfs
		# [quota]         number; quota for this export, in bytes
		def create_export
			zfs(:create, "-p", @params["dataset"])
			update_export
		end
		
		# Update export
		# 
		# Params:
		# [path]          string; name of dataset
		# [share_options] string, optional; passed directly to zfs sharenfs
		# [quota]         number; quota for this export, in bytes
		def update_export
			zfs(:set, "sharenfs=\"#{@params["share_options"]}\"", @params["dataset"]) if @params["share_options"]
			zfs(:set, "quota=#{@params["quota"] == 0 ? "none" : @params["quota"]}", @params["dataset"])
		end
	end
end
