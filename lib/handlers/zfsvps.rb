require 'lib/handlers/vps'
require 'lib/utils/zfs'

class ZfsVPS < VPS
	include ZfsUtils
	
	def create
		zfs(:create, nil, ve_private_ds)
		
		super
	end
	
	def destroy
		syscmd("#{$CFG.get(:bin, :rm)} -rf #{ve_private}")
		zfs(:destroy, nil, ve_private_ds)
		
		syscmd("#{$CFG.get(:bin, :mv)} #{ve_conf} #{ve_conf}.destroyed")
	end
	
	def ve_private_ds
		"#{$CFG.get(:vps, :zfs, :root_dataset)}/#{@veid}"
	end
end
