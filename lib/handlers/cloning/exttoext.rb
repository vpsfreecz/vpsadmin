require 'lib/handlers/clone'

module CloneBackend
	class ExtToExtClone < Clone
		def local_clone
			copy_config
			create_root
			
			syscmd("#{$CFG.get(:bin, :cp)} -a #{@src_vps.ve_private}/ #{@new_vps.ve_private}")
			
			del_ips
		end
		
		def remote_clone
			copy_config
			create_root
			
			rsync = $CFG.get(:vps, :clone, :rsync) \
				.gsub(/%\{rsync\}/, $CFG.get(:bin, :rsync)) \
				.gsub(/%\{src\}/, "#{@src_vps.ve_private}/") \
				.gsub(/%\{dst\}/, @new_vps.ve_private)
			
			syscmd(rsync, [23, 24])
			
			del_ips
		end
	end
end
