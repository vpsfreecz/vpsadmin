require 'lib/handlers/cloning/exttozfs'
require 'lib/utils/zfs'

module CloneBackend
	class ZfsCompatToZfsCompatClone < ExtToZfsClone
		include ZfsUtils
		
		def local_clone
			copy_config
			create_root
			
			zfs(:create, "-p", @new_vps.ve_private_ds)
			
			rsync([:vps, :clone, :rsync], @src_vps.ve_private + "/", @new_vps.ve_private)
			
			del_ips
		end
	end
end
