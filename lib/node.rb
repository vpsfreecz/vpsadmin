require 'lib/executor'

class Node < Executor
	def reboot
		@reboot = true
		ok
	end
	
	def sync_templates
		syscmd("#{$APP_CONFIG[:bin][:rsync]} -a --delete #{@params["sync_path"]} #{$APP_CONFIG[:vz][:vz_root]}/template/cache/")
	end
	
	def post_save(con)
		syscmd("reboot") if @reboot
	end
end
