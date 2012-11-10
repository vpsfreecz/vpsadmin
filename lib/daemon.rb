require 'config'
require 'lib/db'
require 'lib/worker'
require 'lib/command'

module VpsAdmind
	VERSION = "1.4.0-dev"
	
	class Daemon
		def initialize
			@db = Db.new
			@last_change = 0
			@workers = {}
			@queue = []
			@cmds = []
		end
		
		def start
			update_status if Settings::UPDATE_VPS_STATUS
			
			loop do
				sleep(Settings::CHECK_INTERVAL)
				
				update_status if Settings::UPDATE_VPS_STATUS and not @status_thread.alive?
				
				@workers.delete_if do |wid, w|
					until w.done.empty?
						c = w.done.pop
						c.save(@db)
						@cmds.delete(c.id)
					end
					
					not w.working?
				end
				
				next if @workers.size >= Settings::THREADS
				
				@queue.delete_if do |cmd|
					do_command(cmd, true)
				end
				
				#@workers.each { |wid,w| w.work }
				
				next unless @queue.empty?
				
				rs = @db.query("SELECT UNIX_TIMESTAMP(UPDATE_TIME) AS time FROM `information_schema`.`tables` WHERE `TABLE_SCHEMA` = 'vpsadmin' AND `TABLE_NAME` = 'transactions'")
				time = rs.fetch_row.first.to_i
				
				if time > @last_change
					puts "Yeah, we have new set of commands!"
					
					do_commands
					
					@last_change = time
				end
			end
		end
		
		def do_commands
			rs = @db.query("SELECT *, 1 AS depencency_success FROM transactions
							WHERE t_done = 0 AND t_server = #{Settings::SERVER_ID} AND t_depends_on IS NULL
						
							UNION
							
							SELECT t.*, d.t_success AS dependency_success
							FROM transactions t
							INNER JOIN transactions d ON t.t_depends_on = d.t_id
							WHERE
							t.t_done = 0
							AND d.t_done = 1
							AND t.t_server = #{Settings::SERVER_ID}
							
							ORDER BY t_id ASC")
			
			rs.each_hash do |row|
				next if @cmds.include?(row["t_id"])
				
				c = Command.new(row)
				
				unless row["depencency_success"].to_i > 0
					c.dependency_failed(@con)
					next
				end
				
				@cmds << row["t_id"]
				do_command(c)
			end
			
			#@workers.each { |wid,w| w.work }
		end
		
		def do_command(cmd, in_queue = false)
			wid = cmd.worker_id
			
			if @workers.has_key?(wid)
				p "#{cmd.id} assigned to worker"
				@workers[wid] << cmd
			else
				if @workers.size >= Settings::THREADS
					p "#{cmd.id} assigned to queue"
					@queue << cmd unless in_queue
					
					return false
				end
				
				@workers[wid] = Worker.new(cmd)
				
			end
			
			true
		end
		
		def update_status
			@status_thread = Thread.new do
				my = Db.new
				rs = my.query("SELECT vps_id FROM vps WHERE vps_server = #{Settings::SERVER_ID}")
				
				rs.each_hash do |vps|
					ct = VPS.new(vps["vps_id"])
					ct.update_status(my)
				end
				
				my.close
				
				sleep(Settings::STATUS_INTERVAL)
			end
		end
	end
end
