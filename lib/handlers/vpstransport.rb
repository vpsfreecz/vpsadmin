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
<<<<<<< HEAD
		rsync([:vps, :migration, :rsync], {
			:src => "#{@params["src_addr"]}:#{@params["src_ve_private"]}/",
			:dst => @vps.ve_private,
		})
=======
		syscmd($CFG.get(:vps, :migration, :rsync) \
			.gsub(/%\{rsync\}/, $CFG.get(:bin, :rsync)) \
			.gsub(/%\{src\}/, "#{@params["src_addr"]}:#{@params["src_ve_private"]}/") \
			.gsub(/%\{dst\}/, @vps.ve_private), [23, 24])
>>>>>>> 74f27ae3c3fc8ea67e1197c1715f9887256d771b
	end
end
