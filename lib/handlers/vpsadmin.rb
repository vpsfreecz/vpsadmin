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
					:id => w.cmd.id,
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
	
	def kill
		cnt = 0
		msgs = {}
		
		if @params["transactions"] == "all"
			cnt = walk_workers { |w| true }
		elsif @params["types"]
			@params["types"].each do |t|
				killed = walk_workers { |w| w.cmd.type == t }
				
				if killed == 0
					msgs[t] = "No transaction with this type"
				end
				
				cnt += killed
			end
		else
			@params["transactions"].each do |t|
				killed = walk_workers { |w| w.cmd.id == t }
				
				if killed == 0
					msgs[t] = "No such transaction"
				end
				
				cnt += killed
			end
		end
		
		{:ret => :ok, :output => {:killed => cnt, :msgs => msgs}}
	end
	
	def walk_workers
		killed = 0
		
		@daemon.workers do |workers|
			workers.each do |wid, w|
				if yield(w)
					log "Killing transaction #{w.cmd.id}"
					w.kill
					killed += 1
				end
			end
		end
		
		killed
	end
end
