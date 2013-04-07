require 'lib/executor'

# Represents storage node, handles exports, actual implementation provide backends
# in module StorageBackend.
# 
# Backend is set in config :storage -> :method
#
# Parameters of methods in this class may have slightly different meaning in each backend.

class Storage < Executor
	class << self
		alias_method :new_orig, :new
		
		def new(*args)
			StorageBackend.const_get($CFG.get(:storage, :method)).new_orig(*args)
		end
	end
	
	# Create export
	# 
	# Params:
	# [path]          string; path of export
	# [share_options] string, optional
	# [quota]         number; quota for this export, in bytes
	def create_export
		raise CommandNotImplemented
	end
	
	# Update export
	# 
	# Params:
	# [path]          string; path of export
	# [share_options] string, optional
	# [quota]         number; quota for this export, in bytes
	def update_export
		raise CommandNotImplemented
	end
	
	# Update exports status
	def update_status
		
	end
	
	# Returns a list of exports on this node
	def list_exports(db)
		db.query("SELECT e.id, e.dataset, e.path, r.root_dataset, r.root_path FROM storage_export e
		         INNER JOIN storage_root r ON r.id = e.root_id
		         WHERE
		         e.`default` = 'no' AND
		         r.node_id = #{$CFG.get(:vpsadmin, :server_id)}")
	end
end

require 'lib/handlers/storage/zfs'
