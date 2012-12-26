require 'lib/vpsadmind'

module VpsAdminCtl
	VERSION = "1.4.0"
	ACTIONS = [:status, :reload, :stop, :restart, :update]
	
	class RemoteControl
		def initialize(sock)
			@vpsadmind = VpsAdmind.new(sock)
		end
		
		def status
			puts "Version: #{@vpsadmind.version}"
			puts "Uptime: #{Time.new.to_i - @res["start_time"]} s"
			puts "Concurrency: #{@res["threads"]}"
			puts "Workers: #{@res["workers"].size}"
			@res["workers"].each do |wid, w|
				puts "\tWorker ##{wid}: #{w["type"]} (#{Time.new.to_i - w["start"]} s)"
			end
			puts "Exported consoles: #{@res["export_console"] ? @res["consoles"].size : "disabled"}"
			@res["consoles"].each do |veid, usage|
				puts "\tConsole ##{veid}: #{usage} listeners"
			end
		end
		
		def reload
			puts "Config reloaded"
		end
		
		def stop
			puts "Stop scheduled"
		end
		
		def restart
			puts "Restart scheduled"
		end
		
		def update
			puts "Update scheduled"
		end
		
		def is_valid?(cmd)
			ACTIONS.include?(cmd.to_sym)
		end
		
		def exec(cmd, *args)
			return unless is_valid?(cmd)
			
			@vpsadmind.cmd(cmd)
			@reply = @vpsadmind.reply
			
			unless @reply["status"] == "ok"
				return {:status => :failed, :error => @reply["error"]}
			end
			
			@res = @reply["response"]
			
			method(cmd).call(*args)
		end
	end
end
