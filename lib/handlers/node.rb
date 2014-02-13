require 'lib/executor'
require 'lib/utils/zfs'

class Node < Executor
	include ZfsUtils
	
	def init
		return unless zfs?
		
		sharenfs = $CFG.get(:vps, :zfs, :sharenfs)
		
		unless sharenfs.nil?
			ds = $CFG.get(:vps, :zfs, :root_dataset)
			
			if syscmd("#{$CFG.get(:bin, :exportfs)}")[:output] =~ /^\/#{ds}\/\d+$/
				log "ZFS exports already loaded"
				return
			end
			
			log "Reload ZFS exports"
			
			zfs(:set, "sharenfs=off", ds)
			zfs(:set, "sharenfs=\"#{sharenfs}\"", ds)
		end
	end
	
	def reboot
		@reboot = true
		ok
	end
	
	def sync_templates
		syscmd("#{$CFG.get(:bin, :rsync)} -a --delete #{@params["sync_path"]} #{$CFG.get(:vz, :vz_root)}/template/cache/")
	end
	
	def create_config(cfg = nil)
		@params = cfg if cfg
		
		if @params["old_name"]
			File.delete(conf_path(@params["old_name"]))
			
			path = conf_path("original-#{@params["old_name"]}")
			
			if zfs? && File.exists?(path)
				File.delete(path)
			end
		end
		
		f = File.new(conf_path, "w")
		
		if zfs?
			f.write(@params["config"] \
				.gsub(/^DISKSPACE\=\".+\:.+\"/, "") \
				.gsub(/^DISKINODES\=\".+\:.+\"/, "") \
				.gsub(/^QUOTAUGIDLIMIT\=\"\d+\"/, ""))
		else
			f.write(@params["config"])
		end
		
		f.close
		
		if zfs? && @params["config"] =~ /^DISKSPACE\=\".+\:.+\"/
			f = File.new(conf_path("original-#{@params["name"]}"), "w")
			f.write(@params["config"])
			f.close
		end
		
		ok
	end
	
	def delete_config
		File.delete(conf_path) if File.exists?(conf_path)
		
		path = conf_path("original-#{@params["name"]}")
			
		if zfs? && File.exists(path)
			File.delete(path)
		end
		
		ok
	end
	
	def gen_known_hosts
		db = Db.new
		f = File.open($CFG.get(:node, :known_hosts), "w")
		
		rs = db.query("SELECT node_id, `key`, server_ip4 FROM servers s INNER JOIN node_pubkey p ON s.server_id = p.node_id ORDER BY node_id, `type`")
		rs.each_hash do |r|
			f.write("#{r["server_ip4"]} #{r["key"]}\n")
		end
		
		f.close
		ok
	end
	
	def load
		m = /load average\: (\d+\.\d+), (\d+\.\d+), (\d+\.\d+)/.match(syscmd($CFG.get(:bin, :uptime))[:output])
		
		if m
			{1 => m[1], 5 => m[2], 15 => m[3]}
		else
			{}
		end
	end
	
	def conf_path(name = nil)
		"#{$CFG.get(:vz, :vz_conf)}/conf/ve-#{name ? name : @params["name"]}.conf-sample"
	end
	
	def post_save(con)
		syscmd("reboot") if @reboot
	end
end
