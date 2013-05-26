require 'lib/vpsadmind'
require 'lib/utils'

module VpsAdminCtl
	VERSION = "1.9.0-dev"
	ACTIONS = [:status, :reload, :stop, :restart, :update, :kill, :reinit]
	
	class RemoteControl
		def initialize(sock)
			@vpsadmind = VpsAdmind.new(sock)
		end
		
		def status
			if @opts[:workers]
				puts sprintf("%-8s %-5s %-20.19s %-5s %-18.16s %s", "TRANS", "VEID", "HANDLER", "TYPE", "TIME", "STEP") if @opts[:header]
				
				@res["workers"].sort.each do |w|
					puts sprintf("%-8d %-5d %-20.19s %-5d %-18.16s %s", w[1]["id"], w[0], w[1]["handler"], w[1]["type"], format_duration(Time.new.to_i - w[1]["start"]), w[1]["step"])
				end
			end
			
			if @opts[:consoles]
				puts sprintf("%-5s %s", "VEID", "LISTENERS")  if @opts[:header]
				
				@res["consoles"].sort.each do |c|
					puts sprintf("%-5d %d", c[0], c[1])
				end
			end
			
			unless @opts[:workers] || @opts[:consoles]
				puts "Version: #{@vpsadmind.version}"
				puts "Uptime: #{format_duration(Time.new.to_i - @res["start_time"])}"
				puts "Workers: #{@res["workers"].size}/#{@res["threads"]}"
				puts "Queue size: #{@res["queue_size"]}"
				puts "Exported consoles: #{@res["export_console"] ? @res["consoles"].size : "disabled"}"
			end
		end
		
		def reload
			puts "Config reloaded"
		end
		
		def pre_stop
			{:force => @opts[:force]}
		end
		
		def stop
			puts "Stop scheduled"
		end
		
		alias_method :pre_restart, :pre_stop
		
		def restart
			puts "Restart scheduled"
		end
		
		def update
			puts "Update scheduled"
		end
		
		def pre_kill
			if @opts[:all]
				{:transactions => :all}
			elsif @opts[:type]
				if ARGV.size < 2
					$stderr.puts "Kill: missing transaction type(s)"
					return nil
				end
				
				{:types => ARGV[1..-1]}
			else
				if ARGV.size < 2
					$stderr.puts "Kill: missing transaction id(s)"
					return nil
				end
				
				{:transactions => ARGV[1..-1]}
			end
		end
		
		def kill
			@res["msgs"].each do |i, msg|
				puts "#{i}: #{msg}"
			end
			
			puts "" if @res["msgs"].size > 0
			
			puts "Killed #{@res["killed"]} transactions"
		end
		
		def reinit
			puts "Reinitialized"
		end
		
		def is_valid?(cmd)
			ACTIONS.include?(cmd.to_sym)
		end
		
		def exec(cmd, opts)
			return unless is_valid?(cmd)
			
			begin
				@vpsadmind.open
				
				@opts = opts
				params = {}
				
				begin
					params = method("pre_#{cmd}").call
					
					unless params
						$stderr.puts "Command failed"
						return
					end
				rescue NameError
					
				end
				
				@vpsadmind.cmd(cmd, params)
				@reply = @vpsadmind.reply
			rescue
				$stderr.puts "Error occured: #{$!}"
				$stderr.puts "Are you sure that vpsAdmind is running and configured properly?"
				return
			end
			
			unless @reply["status"] == "ok"
				return {:status => :failed, :error => @reply["error"]["error"]}
			end
			
			@res = @reply["response"]
			
			method(cmd).call
		end
	end
end
