require 'lib/handlers/clone'

module CloneBackend
	class ExtToExtClone < Clone
		def local_clone
			copy_configs
			create_root
			
			syscmd("#{$CFG.get(:bin, :cp)} -a #{@src_vps.ve_private}/ #{@new_vps.ve_private}")
		end
		
		def remote_clone
			copy_configs
			create_root
			
			rsync = $CFG.get(:vps, :clone, :rsync) \
				.gsub(/%\{rsync\}/, $CFG.get(:bin, :rsync)) \
				.gsub(/%\{src\}/, "#{@src_vps.ve_private}/") \
				.gsub(/%\{dst\}/, @new_vps.ve_private)
			
			syscmd(rsync, [23, 24])
		end
	end
end
