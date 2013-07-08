require 'lib/handlers/clone'
require 'lib/utils/zfs'

module CloneBackend
	class ZfsToZfsClone < Clone
		include ZfsUtils
		
		def local_clone # FIXME lock and stuff
			copy_config
			create_root
			
			@src_vps.snapshot(@src_vps.ve_private_ds, "clone")
			
			zfs(:clone, nil, "#{@src_vps.ve_private_ds}@clone #{@new_vps.vps_private_ds}")
			zfs(:promote, nil, @new_vps.vps_private_ds)
			
			zfs(:destroy, nil, "#{@src_vps.ve_private_ds}@clone")
			
			del_ips
		end
		
		def remote_clone
			copy_config
			create_root
			
			FIXME
			
			del_ips
		end
	end
end
