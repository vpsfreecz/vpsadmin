#!/usr/bin/env ruby

$: << File.dirname(__FILE__) unless $:.include? File.dirname(__FILE__)

require 'lib/config'
require 'lib/db'

require 'optparse'

require 'rubygems'
require 'json'

options = {
	:config => "/etc/vpsadmin/vpsadmind.yml",
	:dry_run => false,
}

OptionParser.new do |opts|
	opts.on("-c", "--config [CONFIG FILE]", "Config file") do |cfg|
		options[:config] = cfg
	end
	
	opts.on("-d", "--dry-run", "Dry run") do
		options[:dry_run] = true
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
end.parse!

$CFG = AppConfig.new(options[:config])

unless $CFG.load
	exit(false)
end

db = Db.new
servers = {}
vpses = {}

rs = db.query("SELECT vps_id, vps_backup_exclude, server_id, server_name, location_backup_server_id
              FROM vps
              INNER JOIN servers ON server_id = vps_server
              INNER JOIN locations ON location_id = server_location
              WHERE vps_backup_enabled = 1 AND (SELECT t_id FROM transactions WHERE t_type = 5006 AND t_done = 0 AND t_vps = vps_id) IS NULL
              ORDER BY RAND()")
rs.each_hash do |row|
	s_id = row["server_id"].to_i
	
	servers[s_id] ||= row["server_name"]
	vpses[s_id] ||= []
	vpses[s_id] << {:veid => row["vps_id"].to_i, :exclude => row["vps_backup_exclude"].split, :backuper => row["location_backup_server_id"].to_i}
end

until vpses.empty?
	servers.each do |s_id, s_name|
		for i in 1..2
			break unless vpses[s_id]
			
			if vpses[s_id].empty?
				vpses.delete(s_id)
				break
			end
			
			vps = vpses[s_id].pop
			
			params = {
				:server_name => s_name,
				:exclude => vps[:exclude],
			}.to_json
			
			if options[:dry_run]
				puts "BACKUP VPS=#{vps[:veid]}, FROM SERVER=#{s_name}, TO SERVER=#{vps[:backuper]}, PARAMS=#{params}"
			else
				db.prepared("INSERT INTO transactions SET
							t_time = UNIX_TIMESTAMP(NOW()),
							t_m_id = 0,
							t_server = ?,
							t_vps = ?,
							t_type = 5006,
							t_success = 0,
							t_done = 0,
							t_param = ?", vps[:backuper], vps[:veid], params)
			end
		end
	end
end
