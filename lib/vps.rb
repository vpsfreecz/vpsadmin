require 'lib/executor'

class VPS < Executor
	def start
		@update = true
		vzctl(:start, @veid, {}, false, [32,])
		check_onboot
	end
	
	def stop(params = {})
		@update = true
		vzctl(:stop, @veid, {}, false, params[:force] ? [5,66] : [])
		vzctl(:set, @veid, {:onboot => "no"}, true)
	end
	
	def restart
		@update = true
		vzctl(:restart, @veid)
		check_onboot
	end
	
	def create
		vzctl(:create, @veid, {
			:ostemplate => @params["template"],
			:hostname => @params["hostname"],
		})
		check_onboot
		vzctl(:set, @veid, {
			:applyconfig => "basic",
			:nameserver => @params["nameserver"],
		}, true)
	end
	
	def destroy
		stop
		vzctl(:destroy, @veid)
	end
	
	def reinstall
		stop
		destroy
		create
		start
		check_onboot(true)
	end
	
	def set_params
		vzctl(:set, @veid, @params, true)
	end
	
	def features
		start
		vzctl(:set, @veid, {
			:feature => ["nfsd:on", "nfs:on"],
			:capability => "net_admin:on",
		}, true)
		vzctl(:exec, @veid, "mkdir -p /dev/net")
		vzctl(:exec, @veid, "mknod /dev/net/tun c 10 200", false, [8,])
		vzctl(:exec, @veid, "chmod 600 /dev/net/tun")
		vzctl(:exec, @veid, "mknod /dev/fuse c 10 229", false, [8,])
		vzctl(:set, @veid, {
			:iptables => ['ip_conntrack', 'ip_conntrack_ftp', 'ip_conntrack_irc', 'ip_nat_ftp',
			              'ip_nat_irc', 'ip_tables', 'ipt_LOG', 'ipt_REDIRECT', 'ipt_REJECT',
			              'ipt_TCPMSS', 'ipt_TOS', 'ipt_conntrack', 'ipt_helper', 'ipt_length',
			              'ipt_limit', 'ipt_multiport', 'ipt_state', 'ipt_tcpmss', 'ipt_tos',
			              'ipt_ttl', 'iptable_filter', 'iptable_mangle', 'iptable_nat'],
			:numiptent => "1000",
			:devices => ["c:10:200:rw", "c:10:229:rw"],
		}, true)
		restart
	end
	
	def migrate_offline
		syscmd("#{Settings::VZMIGRATE} #{@params["target"]} #{@veid}")
	end
	
	def migrate_online
		begin
			syscmd("#{Settings::VZMIGRATE} --online #{@params["target"]} #{@veid}")
		rescue CommandFailed => err
			@output[:migration_cmd] = err.cmd
			@output[:migration_exitstatus] = err.rc
			@output[:migration_error] = err.output
			{:ret => :warning, :output => migrate_offline[:output]}
		end
	end
	
	def restore
		target = Settings::RESTORE_TARGET % [@veid,]
		syscmd("#{Settings::RM} -rf #{target}") if File.exists?(target)
		syscmd("#{Settings::RDIFF_BACKUP} -r #{@params["datetime"]} #{Settings::BACKUPS_MNT_DIR}/#{@params["backuper"]}.#{Settings::DOMAIN}/#{@veid} #{target}")
		stop(:force => true)
		syscmd("#{Settings::VZQUOTA} off #{@veid} -f", [6,])
		stop
		syscmd("#{Settings::RM} -rf #{Settings::VZ_ROOT}/private/#{@veid}")
		syscmd("#{Settings::MV} #{target} #{Settings::VZ_ROOT}/private/#{@veid}")
		syscmd("#{Settings::VZQUOTA} drop #{@veid}")
		start
	end
	
	def clone
		create
		syscmd("#{Settings::RM} -rf #{Settings::VZ_ROOT}/private/#{@veid}")
		
		if @params["is_local"]
			syscmd("#{Settings::CP} -a #{Settings::VZ_ROOT}/private/#{@params["src_veid"]}/ #{Settings::VZ_ROOT}/private/#{@veid}")
		else
			syscmd("#{Settings::RSYNC} -a #{@params["src_server_ip"]}:#{Settings::VZ_ROOT}/private/#{@params["src_veid"]}/ #{Settings::VZ_ROOT}/private/#{@veid}");
		end
	end
	
	def check_onboot(force = false)
		if (@params.instance_of?(Hash) and @params["onboot"]) or force
			vzctl(:set, @veid, {:onboot => "yes"}, true)
		end
		
		{:ret => :ok}
	end
	
	def load_file(file)
		vzctl(:exec, @veid, "cat #{file}")
	end
	
	def update_status(db)
		up = 0
		nproc = 0
		mem = 0
		disk = 0
		
		begin
			IO.popen("#{Settings::VZLIST} --no-header #{@veid}") do |io|
				status = io.read.split(" ")
				up = status[2] == "running" ? 1 : 0
				nproc = status[1].to_i
				
				mem_str = load_file("/proc/meminfo")[:output]
				mem = (mem_str.match(/^MemTotal\:\s+(\d+) kB$/)[1].to_i - mem_str.match(/^MemFree\:\s+(\d+) kB$/)[1].to_i) / 1024
				
				disk_str = vzctl(:exec, @veid, "#{Settings::DF} -k /")[:output]
				disk = disk_str.split("\n")[1].split(" ")[2].to_i / 1024
			end
		rescue
			
		end
		
		db.prepared(
			"INSERT INTO vps_status (vps_id, timestamp, vps_up, vps_nproc,
			vps_vm_used_mb, vps_disk_used_mb, vps_admin_ver) VALUES
			(?, ?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE
			timestamp = ?, vps_up = ?, vps_nproc = ?, vps_vm_used_mb = ?,
			vps_disk_used_mb = ?, vps_admin_ver = ?",
			@veid.to_i, Time.now.to_i, up, nproc, mem, disk, VpsAdmind::VERSION,
			Time.now.to_i, up, nproc, mem, disk, VpsAdmind::VERSION
		)
	end
	
	def post_save(con)
		update_status(con) if @update
	end
end
