#!/usr/bin/env ruby
# This script orders IP addresses in the database to represent the order in
# which VPSes see them.

require '/opt/vpsadmind/lib/vpsadmind/standalone'

include VpsAdmind::Utils::System
include VpsAdmind::Utils::Log

db = VpsAdmind::Db.new
rs = db.query("
    SELECT vps_id
    FROM vps
    WHERE vps_server = #{$CFG.get(:vpsadmin, :server_id)} AND object_state < 3
    ORDER BY vps_id
")
rs.each_hash do |row|
  vps_id = row['vps_id'].to_i

  puts "VPS #{vps_id}"

  vps_ips = {}
  st = db.prepared_st('SELECT ip_id, ip_addr FROM vps_ip WHERE vps_id = ?', vps_id)
  st.each do |ip_row|
    vps_ips[ ip_row[1] ] = ip_row[0]
  end
  st.close

  order = {4 => 0, 6 => 0}

  begin
    syscmd("vzlist -H -oip #{vps_id}")[:output].strip.split.each do |ip|
      ip_id = vps_ips[ip]
      unless ip_id
        puts "IP #{ip} not found in db"
        next
      end

      v = ip.index(':') ? 6 : 4

      puts "  IP #{ip} (id=#{ip_id},order=#{order[v]})"
      db.prepared(
          'UPDATE vps_ip SET `order` = ? WHERE ip_id = ?',
          order[v], ip_id
      )

      order[v] += 1
    end

  rescue VpsAdmind::CommandFailed => e
    puts "  Error occurred: #{e.message}"
    next
  end
end
