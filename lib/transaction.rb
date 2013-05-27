class Transaction
	@@types = {
		:gen_known_hosts => 5,
	}
	
	def initialize(db = nil)
		@db = db || Db.new
	end
	
	def cluster_wide(p)
		rs = @db.query("SELECT server_id FROM servers ORDER BY server_id")
		rs.each_hash do |r|
			p[:node] = r["server_id"].to_i
			queue(p)
		end
	end
	
	def queue(p)
		param = p[:param].to_json
		param = "{}" if param == "null"
		
		@db.prepared("INSERT INTO transactions (`t_time`, `t_m_id`, `t_server`, `t_vps`, `t_type`, `t_depends_on`, `t_priority`, `t_param`, `t_done`, `t_success`)
		             VALUES (NOW(), ?, ?, ?, ?, ?, ?, ?, 0, 0)",
		             p[:m_id], p[:node], p[:vps], @@types[p[:type]], p[:depends], p[:priority] || 0, param)
	end
end
