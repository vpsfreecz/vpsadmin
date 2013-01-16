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
		db = Db.new
		res_workers = {}
		
		@daemon.workers do |workers|
			workers.each do |wid, w|
				h = w.cmd.handler
				
				res_workers[wid] = {
					:type => w.cmd.trans["t_type"].to_i,
					:handler => "#{h[:class]}.#{h[:method]}",
					:step => w.cmd.step,
					:start => w.cmd.time_start,
				}
			end
		end
		
		consoles = {}
		VzConsole.consoles do |c|
			c.each do |veid, console|
				consoles[veid] = console.usage
			end
		end
		
		st = db.prepared_st("SELECT COUNT(t_id) AS cnt FROM transactions WHERE t_server = ? AND t_done = 0", $CFG.get(:vpsadmin, :server_id))
		q_size = st.fetch()[0]
		st.close
		
		{:ret => :ok,
			:output => {
				:workers => res_workers,
				:threads => $CFG.get(:vpsadmin, :threads),
				:export_console => @daemon.export_console,
				:consoles => consoles,
				:start_time => @daemon.start_time.to_i,
				:queue_size => q_size - res_workers.size,
			}
		}
	end
end
