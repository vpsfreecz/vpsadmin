require 'lib/db'
require 'lib/worker'
require 'lib/command'
require 'lib/console'
require 'lib/remote'
require 'lib/transaction'

require 'rubygems'
require 'eventmachine'

module VpsAdmind
	VERSION = "1.9.1"
	DB_VERSION = 3
	
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
			@threads = {}
			
			Command.load_handlers()
		end
		
		def init
			@fw = Firewall.new
			@fw.init(@db)
		end
		
		def start
			check_db_version
			
			loop do
				sleep($CFG.get(:vpsadmin, :check_interval))
				
				run_threads
				
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
				
				$stdout.flush
				$stderr.flush
			end
		end
		
		def do_commands
			rs = @db.query("SELECT * FROM (
								(SELECT *, 1 AS depencency_success FROM transactions
								WHERE t_done = 0 AND t_server = #{$CFG.get(:vpsadmin, :server_id)} AND t_depends_on IS NULL
								GROUP BY t_vps, t_priority, t_id)
							
								UNION ALL
								
								(SELECT t.*, d.t_success AS dependency_success
								FROM transactions t
								INNER JOIN transactions d ON t.t_depends_on = d.t_id
								WHERE
								t.t_done = 0
								AND d.t_done = 1
								AND t.t_server = #{$CFG.get(:vpsadmin, :server_id)}
								GROUP BY t_vps, t_priority, t_id)
							
								ORDER BY t_priority DESC, t_id ASC LIMIT #{$CFG.get(:vpsadmin, :threads)}
							) tmp
							GROUP BY t_vps, t_priority, t_id ORDER BY t_priority DESC, t_id ASC")
			
			rs.each_hash do |row|
				c = Command.new(row)
				
				unless row["depencency_success"].to_i > 0
					c.dependency_failed(@db)
					next
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
		
		def run_threads
			if !@threads[:status] || !@threads[:status].alive?
				@threads[:status] = Thread.new do
					loop do
						log "Update status"
						
						update_status
						
						sleep($CFG.get(:vpsadmin, :status_interval))
					end
				end
			end
			
			if !@threads[:resources] || !@threads[:resources].alive?
				@threads[:resources] = Thread.new do
					loop do
						log "Update resources"
						
						update_resources
						
						sleep($CFG.get(:vpsadmin, :resources_interval))
					end
				end
			end
		end
		
		def update_all
			update_status
			update_resources
		end
		
		def update_status
			my = Db.new
			my.prepared("INSERT INTO servers_status
						SET server_id = ?, timestamp = UNIX_TIMESTAMP(NOW()), cpu_load = ?, daemon = ?, vpsadmin_version = ?",
						$CFG.get(:vpsadmin, :server_id), Node.new(0).load[5], 0, VpsAdmind::VERSION)
			
			my.close
		end
		
		def update_resources
			my = Db.new
			
			if $CFG.get(:vpsadmin, :update_vps_status)
				rs = my.query("SELECT vps_id FROM vps WHERE vps_server = #{$CFG.get(:vpsadmin, :server_id)}")
				
				rs.each_hash do |vps|
					ct = VPS.new(vps["vps_id"])
					ct.update_status(my)
				end
				
				Firewall.mutex.synchronize do
					fw = Firewall.new
					fw.update_traffic(my)
					fw.reset_traffic_counter
				end
			end
			
			if $CFG.get(:storage, :update_status)
				Storage.new(0).update_status
			end
			
			my.close
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
		
		def check_db_version
			informed = false
			
			loop do
				@@mutex.synchronize do
					exit(@@exitstatus) unless @@run
				end
				
				rs = @db.query("SELECT cfg_value FROM sysconfig WHERE cfg_name = 'db_version'")
				ver = rs.fetch_row.first.to_i
				
				if VpsAdmind::DB_VERSION != ver
					unless informed
						log "Database version does not match: required #{VpsAdmind::DB_VERSION}, current #{ver}"
						$stdout.flush
						
						informed = true
					end
					
					sleep(10)
				else
					return
				end
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
