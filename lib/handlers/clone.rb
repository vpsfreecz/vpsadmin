require 'lib/handlers/vpstransport'

class Clone < VpsTransport
	class << self
		alias_method :new_orig, :new
		
		def new(*args)
			src = args[1]["src_node_type"].to_sym
			dst = args[1]["dst_node_type"].to_sym
			
			klass = nil
			
			if src == :ext4 && dst == :ext4
				klass = :ExtToExtClone
				
			elsif (src == :ext4 && dst == :zfs) || (src == :ext4 && dst == :zfs_compat)
				klass = :ExtToZfsClone
				
			elsif (src == :zfs && dst == :ext4) || (src == :zfs_compat && dst == :ext4)
				klass = :ZfsToExtClone
				
			elsif src == :zfs_compat && dst == :zfs_compat
				klass = :ZfsCompatToZfsCompatClone
				
			else
				klass = :ZfsToZfsClone
			end
			
			CloneBackend.const_get(klass).new_orig(*args)
		end
	end
	
	def initialize(*args)
		super
		
		@src_vps = VPS.new(@params["src_veid"])
		@new_vps = VPS.new(@veid)
	end
	
	# Clone VPS locally, run on destination vz node
	# 
	# Params:
	# [src_node_type]
	# [dst_node_type]
	# [src_veid]
	# [src_addr]
	def local_clone
		raise CommandNotImplemented
	end
	
	# Clone VPS remotely, run on destination vz node
	def remote_clone
		raise CommandNotImplemented
	end
	
	def copy_config
		scp("#{@params["src_addr"]}:#{$CFG.get(:vz, :vz_conf)}/conf/#{@params["src_veid"]}.conf", "#{$CFG.get(:vz, :vz_conf)}/conf/#{@veid}.conf")
		
		vzctl(:set, @veid, {:private => @new_vps.ve_private, :root => @new_vps.ve_root}, true)
	end
	
	def del_ips
		vzctl(:set, @veid, {:ipdel => "all"}, true)
	end
end

require 'lib/handlers/cloning/exttoext'
require 'lib/handlers/cloning/exttozfs'
require 'lib/handlers/cloning/zfstoext'
require 'lib/handlers/cloning/zfstozfs'
require 'lib/handlers/cloning/zfscompattozfscompat'
