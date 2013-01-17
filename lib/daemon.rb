require 'lib/db'
require 'lib/worker'
require 'lib/command'
require 'lib/console'
require 'lib/remote'

require 'rubygems'
require 'eventmachine'

module VpsAdmind
	VERSION = "1.5.2"
	
	EXIT_OK = 0
	EXIT_ERR = 1
	EXIT_STOP = 100
	EXIT_RESTART = 150
	EXIT_UPDATE = 200
	
	class Daemon
		attr_reader :start_time, :export_console
		
		@@run = true
		@@exitstatus = 0
		@@mutex = Mutex.new
		
		def initialize
			@db = Db.new
			@last_change = 0
			@workers = {}
			@m_workers = Mutex.new
			@start_time = Time.new
			@export_console = false
			@cmd_counter = 0
			
			Command.load_handlers()
		end
		
		def init
			@fw = Firewall.new
			@fw.init(@db)
		end
		
		def start
			update_status
			
			loop do
				sleep($CFG.get(:vpsadmin, :check_interval))
				
				update_status unless @status_thread.alive?
				
				catch (:next) do
					@m_workers.synchronize do
						@workers.delete_if do |wid, w|
							if not w.working?
								c = w.cmd
								c.save(@db)
								
								next true
							end
							
							false
						end
						
						throw :next if @workers.size >= $CFG.get(:vpsadmin, :threads)
						
						@@mutex.synchronize do
							unless @@run
								exit(@@exitstatus) if @workers.empty?
								throw :next
							end
						end
						
						rs = @db.query("SELECT UNIX_TIMESTAMP(UPDATE_TIME) AS time FROM `information_schema`.`tables` WHERE `TABLE_SCHEMA` = 'vpsadmin' AND `TABLE_NAME` = 'transactions'")
						time = rs.fetch_row.first.to_i
						
						if time > @last_change
							do_commands
							
							@last_change = time
						end
					end
				end
			end
		end
		
		def do_commands
			rs = @db.query("SELECT * FROM (
								(SELECT *, 1 AS depencency_success FROM transactions
								WHERE t_done = 0 AND t_server = #{$CFG.get(:vpsadmin, :server_id)} AND t_depends_on IS NULL
								GROUP BY t_vps, t_priority)
							
								UNION ALL
								
								(SELECT t.*, d.t_success AS dependency_success
								FROM transactions t
								INNER JOIN transactions d ON t.t_depends_on = d.t_id
								WHERE
								t.t_done = 0
								AND d.t_done = 1
								AND t.t_server = #{$CFG.get(:vpsadmin, :server_id)}
								GROUP BY t_vps, t_priority)
							
								ORDER BY t_priority DESC, t_id ASC LIMIT #{$CFG.get(:vpsadmin, :threads)}
							) tmp
							GROUP BY t_vps")
			
			rs.each_hash do |row|
				c = Command.new(row)
				
				unless row["depencency_success"].to_i > 0
					c.dependency_failed(@db)
					return
				end
				
				do_command(c)
			end
		end
		
		def do_command(cmd)
			wid = cmd.worker_id
			
			if !@workers.has_key?(wid) && @workers.size < $CFG.get(:vpsadmin, :threads)
				@cmd_counter += 1
				@workers[wid] = Worker.new(cmd)
			end
		end
		
		def update_status
			@status_thread = Thread.new do
				loop do
					my = Db.new
					
					if $CFG.get(:vpsadmin, :update_vps_status)
						rs = my.query("SELECT vps_id FROM vps WHERE vps_server = #{$CFG.get(:vpsadmin, :server_id)}")
						
						rs.each_hash do |vps|
							ct = VPS.new(vps["vps_id"])
							ct.update_status(my)
						end
						
						fw = Firewall.new
						fw.read_traffic.each do |ip, traffic|
							next if traffic[:in] == 0 and traffic[:out] == 0
							
							st = my.prepared_st("UPDATE transfered SET tr_in = tr_in + ?, tr_out = tr_out + ?, tr_time = UNIX_TIMESTAMP(NOW())
												WHERE tr_ip = ? AND tr_time >= UNIX_TIMESTAMP(CURDATE())",
												traffic[:in], traffic[:out], ip)
							
							unless st.affected_rows == 1
								st.close
								my.prepared("INSERT INTO transfered SET tr_in = ?, tr_out = ?, tr_ip = ?, tr_time = UNIX_TIMESTAMP(NOW())",  traffic[:in], traffic[:out], ip)
							end
						end
						
						fw.reset_traffic_counter
					end
					
					my.prepared("INSERT INTO servers_status
								SET server_id = ?, timestamp = UNIX_TIMESTAMP(NOW()), cpu_load = ?, daemon = ?, vpsadmin_version = ?",
								$CFG.get(:vpsadmin, :server_id), 0, 0, VpsAdmind::VERSION)
					
					my.close
					
					sleep($CFG.get(:vpsadmin, :status_interval))
				end
			end
		end
		
		def start_em(console, remote)
			@export_console = console
			
			RemoteControl.load_handlers if remote
			
			@em_thread = Thread.new do
				EventMachine.run do
					EventMachine.start_server($CFG.get(:console, :host), $CFG.get(:console, :port), VzServer) if console
					EventMachine.start_unix_domain_server($CFG.get(:remote, :socket), RemoteControl, self) if remote
				end
			end
		end
		
		def workers
			@m_workers.synchronize do
				yield(@workers)
			end
		end
		
		def Daemon.safe_exit(status)
			@@mutex.synchronize do
				@@run = false
				@@exitstatus = status
			end
		end
	end
end
