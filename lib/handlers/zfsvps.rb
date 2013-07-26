require 'lib/handlers/vps'
require 'lib/utils/zfs'

class ZfsVPS < VPS
	include ZfsUtils
	
	class << self
		def new(*args)
			ZfsVPS.new_orig(*args)
		end
	end
	
	def create
		zfs(:create, nil, ve_private_ds)
		
		super
	end
	
	def destroy
		syscmd("#{$CFG.get(:bin, :rmdir)} #{ve_root}")
		syscmd("#{$CFG.get(:bin, :rm)} -rf #{ve_private}")
		
		zfs(:destroy, "-r", ve_private_ds)
		
		Dir.glob("#{$CFG.get(:vz, :vz_conf)}/conf/#{@veid}.{mount,umount,conf}").each do |cfg|
			syscmd("#{$CFG.get(:bin, :mv)} #{cfg} #{cfg}.destroyed")
		end
		
		ok
	end
	
	def applyconfig
		n = Node.new
		
		@params["configs"].each do |cfg|
			vzctl(:set, @veid, {:applyconfig => cfg, :setmode => "restart"}, true)
			
			path = n.conf_path("original-#{cfg}")
			
			if File.exists?(path)
				content = File.new(path).read
				
				m = nil
				quota = nil
				
				if (m = content.match(/^DISKSPACE\=\"\d+\:(\d+)\"/)) # vzctl saves diskspace in kB
					quota = m[1].to_i * 1024
					
				elsif (m = content.match(/^DISKSPACE\=\"\d+[GMK]\:(\d+[GMK])\"/))
					quota = m[1]
				end
				
				if quota
					zfs(:set, "refquota=#{quota}", ve_private_ds)
				end
			end
		end
		
		ok
	end
	
	def snapshot(ds, name)
		zfs(:snapshot, nil, "#{ds}@#{name}")
	end
	
	def rotate_snapshots
		snapshots = list_snapshots(ve_private_ds)
		
		snapshots[0..-2].each do |s|
			zfs(:destroy, nil, s)
		end
		
		ok
	end
	
	def ve_private_ds
		"#{$CFG.get(:vps, :zfs, :root_dataset)}/#{@veid}"
	end
end
