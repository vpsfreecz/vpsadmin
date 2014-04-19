require 'pp'
require 'lib/vpsadmind'
require 'lib/utils'

module VpsAdminCtl
	VERSION = '1.18.2'
	ACTIONS = [:status, :reload, :stop, :restart, :update, :kill, :reinit,
             :refresh, :install, :show]
	
	class RemoteControl
		def initialize(options)
			@global_opts = options
			@vpsadmind = VpsAdmind.new(options[:sock])
		end
		
		def status
			if @opts[:workers]
				puts sprintf("%-8s %-5s %-20.19s %-5s %-18.16s %-8s %s", "TRANS", "VEID", "HANDLER", "TYPE", "TIME", "PID", "STEP") if @opts[:header]
				
				@res["workers"].sort.each do |w|
					puts sprintf("%-8d %-5d %-20.19s %-5d %-18.16s %-8s %s",
                       w[1]["id"],
                       w[0],
                       w[1]["handler"],
                       w[1]["type"],
                       format_duration(Time.new.to_i - w[1]["start"]),
                       w[1]["pid"],
                       w[1]["step"]
               )
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
			@res.each do |k, v|
				puts "#{v} rules for IPv#{k}"
			end
		end
		
		def refresh
			puts "Refreshed"
		end
		
		def pre_install
			if @opts[:create] && (@opts[:addr].nil? || @opts[:location].nil?)
				raise OptionParser::MissingArgument.new("--addr and --location must be specified if creating new node")
			end
			
			@opts
		end
		
		def install
			if @global_opts[:parsable]
				puts @res["node_id"]
			else
				puts "#{@opts[:create] ? "Installed" : "Updated"} node #{@res["node_id"]}"
			end
    end

    def pre_show
      if ARGV.size < 2
        $stderr.puts 'show: missing resource'
        return nil
      end

      {:resource => ARGV[1]}
    end

    def show
      case ARGV[1]
        when 'config'
          cfg = @res['config']

          if ARGV[2]
            ARGV[2].split('.').each do |s|
              cfg = cfg[cfg.instance_of?(Array) ? s.to_i : s]
            end
          end

          if @global_opts[:parsable]
            puts cfg.to_json
          else
            pp cfg
          end

        when 'queue'
          q = @res['queue']

          if @global_opts[:parsable]
            puts q.to_json
          else
            puts sprintf(
              '%-8s %-3s %-4s %-5s %-5s %-5s %-8s %-18.16s',
              'TRANS', 'URG', 'PRIO', 'USER', 'VEID', 'TYPE', 'DEP', 'WAITING'
            )

            q.each do |t|
              puts sprintf(
                '%-8d %-3d %-4d %-5d %-5d %-5d %-8d %-18.16s',
                t['id'], t['urgent'] ? 1 : 0, t['priority'], t['m_id'], t['vps_id'],
                t['type'], t['depends_on'],
                format_duration(Time.new.to_i - t['time'])
               )
            end
          end

        else
          pp @res
      end

      nil
    end
		
		def autodetect
			puts "Done"
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
				return {:status => :failed, :error => "Cannot connect to vpsAdmind"}
			end
			
			unless @reply["status"] == "ok"
				return {:status => :failed, :error => @reply["error"]["error"]}
			end
			
			@res = @reply["response"]
			
			method(cmd).call
		end
	end
end
