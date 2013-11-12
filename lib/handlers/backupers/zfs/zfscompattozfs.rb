require 'lib/handlers/backupers/zfs/exttozfs'
require 'lib/utils/zfs'

require 'fileutils'
require 'tempfile'

module BackuperBackend
	class ZfsCompatToZfs < ExtToZfs
		def backup
			mount_vps do
				super
			end
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
			mount_vps do
				vps = ZfsVPS.new(@veid)
				src = "#{@params["node_addr"]}:/#{vps.ve_private_ds}.restoring"
				dst = "#{mountpoint}.restoring"
				
				Dir.mkdir(dst) unless File.exists?(dst)
				syscmd("#{$CFG.get(:bin, :mount)} #{src} #{dst}")
				
				super
				
				syscmd("#{$CFG.get(:bin, :umount)} #{dst}")
				Dir.rmdir(dst)
			end
		end
		
		def restore_finish
			vps = ZfsVPS.new(@veid)
			tmp = "#{vps.ve_private_ds}.restoring"
			
			vps.honor_state do
				vps.stop
				
				acquire_lock(Db.new) do
					zfs(:set, "refquota=#{zfs(:get, "-H -ovalue refquota", vps.ve_private_ds)[:output].strip}", tmp)
					zfs(:destroy, "-r", vps.ve_private_ds)
					zfs(:rename, nil, "#{tmp} #{vps.ve_private_ds}")
					
					zfs(:mount, nil, vps.ve_private_ds, [1,]) # FIXME: why is it unmounted?
				end
			end
		end
	end
end
