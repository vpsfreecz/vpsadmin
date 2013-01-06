require 'lib/executor'

class Node < Executor
	def reboot
		@reboot = true
		ok
	end
	
	def sync_templates
		syscmd("#{$APP_CONFIG[:bin][:rsync]} -a --delete #{@params["sync_path"]} #{$APP_CONFIG[:vz][:vz_root]}/template/cache/")
	end
	
	def create_config
		f = File.new(conf_path, "w")
		f.write(@params["config"])
		f.close
		ok
	end
	
	def delete_config
		File.delete(conf_path) if File.exists?(conf_path)
		ok
	end
	
	def conf_path
		"#{$APP_CONFIG[:vz][:vz_conf]}/conf/ve-#{@params["name"]}.conf-sample"
	end
	
	def post_save(con)
		syscmd("reboot") if @reboot
	end
end
