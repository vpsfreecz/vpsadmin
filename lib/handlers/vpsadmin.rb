require 'lib/executor'
require 'lib/daemon'

class VpsAdmin < Executor
	def reload
		Process.kill("HUP", Process.pid)
		ok
	end
	
	def stop
		VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_STOP)
		ok
	end
	
	def restart
		VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_RESTART)
		ok
	end
	
	def update
		VpsAdmind::Daemon.safe_exit(VpsAdmind::EXIT_UPDATE)
		ok
	end
	
	def status
		res_workers = {}
			
		@daemon.workers do |workers|
			workers.each do |wid, w|
				res_workers[wid] = {:type => w.cmd.trans["t_type"].to_i, :start => w.cmd.time_start}
			end
		end
		
		consoles = {}
		VzConsole.consoles do |c|
			c.each do |veid, console|
				consoles[veid] = console.usage
			end
		end
		
		{:ret => :ok,
			:output => {
				:workers => res_workers,
				:threads => $APP_CONFIG[:vpsadmin][:threads],
				:export_console => @daemon.export_console,
				:consoles => consoles,
				:start_time => @daemon.start_time.to_i
			}
		}
	end
end
