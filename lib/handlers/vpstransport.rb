require 'lib/executor'

class VpsTransport < Executor
	def create_root
		path = "#{$CFG.get(:vz, :vz_root)}/root/#{@veid}"
		
		if File.exists?(path)
			begin
				Dir.rmdir(path)
			rescue SystemCallError => err
				raise CommandFailed.new("rmdir", 1, err.to_s)
			end
		end
		
		syscmd("#{$CFG.get(:bin, :mkdir)} #{path}")
	end
	
	def sync_private
		syscmd($CFG.get(:vps, :migration, :rsync) \
			.gsub(/%\{rsync\}/, $CFG.get(:bin, :rsync)) \
			.gsub(/%\{src\}/, "#{@params["src_addr"]}:#{@params["src_ve_private"]}/") \
			.gsub(/%\{dst\}/, @vps.ve_private), [23, 24])
	end
end
