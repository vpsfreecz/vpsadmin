require 'lib/handlers/clone'

module CloneBackend
	class ZfsToExtClone < Clone
		def remote_clone
			copy_config
			create_root
			
			rsync = $CFG.get(:vps, :clone, :rsync) \
				.gsub(/%\{rsync\}/, $CFG.get(:bin, :rsync)) \
				.gsub(/%\{src\}/, "#{@params["src_addr"]}:#{$CFG.get(:vz, :vz_root)}/private/#{@params["src_veid"]}/private/") \
				.gsub(/%\{dst\}/, "#{$CFG.get(:vz, :vz_root)}/private/#{@veid}")
			
			syscmd(rsync, [23, 24])
			
			vzctl(:set, @veid, {:root => @new_vps.ve_root, :private => @new_vps.ve_private}, true)
			del_ips
		end
	end
end
