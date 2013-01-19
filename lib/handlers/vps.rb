require 'lib/executor'
require 'lib/handlers/backuper'

class VPS < Executor
	def start
		@update = true
		ensure_mountfile
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
		ensure_mountfile
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
	
	def applyconfig
		@params["configs"].each do |cfg|
			vzctl(:set, @veid, {:applyconfig => cfg}, true)
		end
		ok
	end
	
	def features
		stop
		vzctl(:set, @veid, {
			:feature => ["nfsd:on", "nfs:on", "ppp:on"],
			:capability => "net_admin:on",
			:iptables => ['ip_conntrack', 'ip_conntrack_ftp', 'ip_conntrack_irc', 'ip_nat_ftp',
			              'ip_nat_irc', 'ip_tables', 'ipt_LOG', 'ipt_REDIRECT', 'ipt_REJECT',
			              'ipt_TCPMSS', 'ipt_TOS', 'ipt_conntrack', 'ipt_helper', 'ipt_length',
			              'ipt_limit', 'ipt_multiport', 'ipt_state', 'ipt_tcpmss', 'ipt_tos',
			              'ipt_ttl', 'iptable_filter', 'iptable_mangle', 'iptable_nat'],
			:numiptent => "1000",
			:devices => ["c:10:200:rw", "c:10:229:rw", "c:108:0:rw"],
		}, true)
		start
		vzctl(:exec, @veid, "mkdir -p /dev/net")
		vzctl(:exec, @veid, "mknod /dev/net/tun c 10 200", false, [8,])
		vzctl(:exec, @veid, "chmod 600 /dev/net/tun")
		vzctl(:exec, @veid, "mknod /dev/fuse c 10 229", false, [8,])
		vzctl(:exec, @veid, "mknod /dev/ppp c 108 0", false, [8,])
		vzctl(:exec, @veid, "chmod 600 /dev/ppp")
	end
	
	def migrate_offline
		stop if @params["stop"]
		syscmd("#{$CFG.get(:vz, :vzmigrate)} #{@params["target"]} #{@veid}")
	end
	
	def migrate_online
		begin
			syscmd("#{$CFG.get(:vz, :vzmigrate)} --online #{@params["target"]} #{@veid}")
		rescue CommandFailed => err
			@output[:migration_cmd] = err.cmd
			@output[:migration_exitstatus] = err.rc
			@output[:migration_error] = err.output
			{:ret => :warning, :output => migrate_offline[:output]}
		end
	end
	
	def clone
		create
		syscmd("#{$CFG.get(:bin, :rm)} -rf #{$CFG.get(:vz, :vz_root)}/private/#{@veid}")
		
		if @params["is_local"]
			syscmd("#{$CFG.get(:bin, :cp)} -a #{$CFG.get(:vz, :vz_root)}/private/#{@params["src_veid"]}/ #{$CFG.get(:vz, :vz_root)}/private/#{@veid}")
		else
			syscmd("#{$CFG.get(:bin, :rsync)} -a #{@params["src_server_ip"]}:#{$CFG.get(:vz, :vz_root)}/private/#{@params["src_veid"]}/ #{$CFG.get(:vz, :vz_root)}/private/#{@veid}");
		end
	end
	
	def check_onboot(force = false)
		if (@params.instance_of?(Hash) and @params["onboot"]) or force
			vzctl(:set, @veid, {:onboot => "yes"}, true)
		end
		
		ok
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
			IO.popen("#{$CFG.get(:vz, :vzlist)} --no-header #{@veid}") do |io|
				status = io.read.split(" ")
				up = status[2] == "running" ? 1 : 0
				nproc = status[1].to_i
				
				mem_str = load_file("/proc/meminfo")[:output]
				mem = (mem_str.match(/^MemTotal\:\s+(\d+) kB$/)[1].to_i - mem_str.match(/^MemFree\:\s+(\d+) kB$/)[1].to_i) / 1024
				
				disk_str = vzctl(:exec, @veid, "#{$CFG.get(:bin, :df)} -k /")[:output]
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
	
	def ensure_mountfile
		p = "#{$CFG.get(:vz, :vz_conf)}/conf/#{@veid}.mount"
		
		unless File.exists?(p)
			File.open(p, "w") do |f|
				f.write(File.open("scripts/ve.mount").read.gsub(/%%BACKUP_SERVER%%/, "storage.prg.#{$CFG.get(:vpsadmin, :domain)}"))
			end
			syscmd("#{$CFG.get(:bin, :chmod)} +x #{p}")
		end
		
		ok
	end
	
	def post_save(con)
		update_status(con) if @update
	end
end
