require 'lib/executor'

class Firewall < Executor
	def initialize
		
	end
	
	def init(db)
		[4, 6].each do |v|
			iptables(v, {:N => "aztotal"})
			iptables(v, {:Z => "aztotal"})
			iptables(v, {:A => "FORWARD", :j => "aztotal"})
		end
		
		# FIXME: OSPF
		
		rs = db.query("SELECT ip_addr, ip_v FROM vps_ip")
		rs.each_hash do |ip|
			v = ip["ip_v"].to_i
			iptables(v, {:A => "aztotal", :s => ip["ip_addr"]})
			iptables(v, {:A => "aztotal", :d => ip["ip_addr"]})
		end
	end
	
	def read_traffic
		ret = {}
		{4 => "0.0.0.0/0", 6 => "::/0"}.each do |v, all|
			iptables(v, {:L => "aztotal", "-nvx" => nil})[:output].split("\n")[2..-1].each do |l|
				fields = l.split(/\s+/)
				src = fields[7]
				dst = fields[8]
				ip = src == all ? dst : src
				
				ret[ip] = {} unless ret.include?(ip)
				ret[ip][src == all ? :in : :out] = fields[2].to_i
			end
		end
		
		ret
	end
	
	def reset_traffic_counter
		[4, 6].each do |v|
			iptables(v, {:Z => "aztotal"})
		end
	end
	
	def iptables(ver, opts)
		options = []
		
		if opts.instance_of?(Hash)
			opts.each do |k, v|
				k = k.to_s
				options << "#{k.start_with?("-") ? "" : (k.length > 1 ? "--" : "-")}#{k}#{v ? " " : ""}#{v}"
			end
		else
			options << opts
		end
		
		syscmd("#{ver == 4 ? Settings::IPTABLES : Settings::IP6TABLES} #{options.join(" ")}")
	end
end
