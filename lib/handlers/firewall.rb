require 'lib/executor'

class Firewall < Executor
	def initialize(veid = -1, params = {})
		if veid.to_i > -1
			super(veid, params)
		else
			@m_attr = Mutex.new
		end
	end
	
	def init(db)
		[4, 6].each do |v|
			ret = iptables(v, {:N => "aztotal"}, [1,])
			
			# Chain already exists, we don't have to continue
			if ret[:exitstatus] == 1
				log "Skipping init for IPv#{v}, chain aztotal already exists"
				next
			end
			
			iptables(v, {:Z => "aztotal"})
			iptables(v, {:A => "FORWARD", :j => "aztotal"})
			
			rs = db.query("SELECT ip_addr, ip_v FROM vps_ip, servers WHERE server_id = #{$CFG.get(:vpsadmin, :server_id)} AND ip_v = #{v} AND ip_location = server_location")
			rs.each_hash do |ip|
				reg_ip(ip["ip_addr"], v)
			end
		end
		
		# FIXME: OSPF
	end
	
	def reg_ip(addr, v)
		iptables(v, {:A => "aztotal", :s => addr})
		iptables(v, {:A => "aztotal", :d => addr})
	end
	
	def unreg_ip(addr, v)
		iptables(v, {:Z => "aztotal", :s => addr})
		iptables(v, {:Z => "aztotal", :d => addr})
	end
	
	def reg_ips
		@params["ip_addrs"].each do |ip|
			reg_ip(ip["addr"], ip["ver"])
		end
		
		ok
	end
	
	def read_traffic
		ret = {}
		{4 => "0.0.0.0/0", 6 => "::/0"}.each do |v, all|
			iptables(v, {:L => "aztotal", "-nvx" => nil})[:output].split("\n")[2..-1].each do |l|
				fields = l.strip.split(/\s+/)
				src = fields[v == 4 ? 6 : 5]
				dst = fields[v == 4 ? 7 : 6]
				ip = src == all ? dst : src
				
				if v == 6
					ip = ip.split("/").first
				end
				
				ret[ip] ||= {}
				ret[ip][src == all ? :in : :out] = fields[1].to_i
			end
		end
		
		ret
	end
	
	def reset_traffic_counter
		[4, 6].each do |v|
			iptables(v, {:Z => "aztotal"})
		end
	end
	
	def iptables(ver, opts, valid_rcs = [])
		options = []
		
		if opts.instance_of?(Hash)
			opts.each do |k, v|
				k = k.to_s
				options << "#{k.start_with?("-") ? "" : (k.length > 1 ? "--" : "-")}#{k}#{v ? " " : ""}#{v}"
			end
		else
			options << opts
		end
		
		syscmd("#{$CFG.get(:bin, ver == 4 ? :iptables : :ip6tables)} #{options.join(" ")}", valid_rcs)
	end
end
