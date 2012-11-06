require 'lib/executor'

class Node < Executor
	def reboot
		@reboot = true
		{:ret => true}
	end
	
	def sync_templates
		syscmd("#{Settings::RSYNC} -a --delete #{@params["sync_path"]} /vz/template/cache/")
	end
	
	def post_save(con)
		syscmd("reboot") if @reboot
	end
end
