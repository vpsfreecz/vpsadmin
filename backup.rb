#!/usr/bin/env ruby

$: << File.dirname(__FILE__) unless $:.include? File.dirname(__FILE__)

require 'lib/config'
require 'lib/db'
require 'lib/transaction'

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

# Backup ext nodes
servers = {}
vpses = {}

rs = db.query("SELECT vps_id, vps_backup_exclude, server_id, server_name, r.node_id AS backuper_server_id,
                      e.dataset, e.path, r.root_dataset, r.root_path, s.fstype, server_ip4
              FROM vps
              INNER JOIN servers s ON server_id = vps_server
              INNER JOIN locations ON location_id = server_location
              INNER JOIN storage_export e ON e.id = vps_backup_export
              INNER JOIN storage_root r ON r.id = e.root_id
              INNER JOIN members m ON vps.m_id = m.m_id
              WHERE
                s.fstype IN ('ext4', 'zfs_compat') AND
                vps_deleted IS NULL AND m.m_state = 'active' AND
                vps_backup_enabled = 1 AND (SELECT t_id FROM transactions WHERE t_type = 5006 AND t_done = 0 AND t_vps = vps_id) IS NULL
              ORDER BY RAND()")
rs.each_hash do |row|
  s_id = row["server_id"].to_i

  servers[s_id] ||= row["server_name"]
  vpses[s_id] ||= []
  vpses[s_id] << {
      :veid => row["vps_id"].to_i,
      :dataset => row["root_dataset"] + "/" + row["dataset"],
      :path => row["root_path"] + "/" + row["path"],
      :exclude => row["vps_backup_exclude"].split,
      :backuper => row["backuper_server_id"].to_i,
      :fstype => row["fstype"],
      :node_addr => row["server_ip4"],
  }
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
          :src_node_type => vps[:fstype],
          :dst_node_type => :zfs, # FIXME
          :server_name => s_name,
          :node_addr => vps[:node_addr],
          :exclude => vps[:exclude],
          :dataset => vps[:dataset],
          :path => vps[:path],
          :rotate_backups => true,
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

# Backup ZFS nodes
rs = db.query("SELECT vps_id, s.server_id AS node_id, server_ip4, server_name, r.node_id AS backuper_server_id, e.dataset, e.path, r.root_dataset, r.root_path
              FROM vps v
              INNER JOIN servers s ON server_id = vps_server
              INNER JOIN locations ON location_id = server_location
              INNER JOIN storage_export e ON e.id = vps_backup_export
              INNER JOIN storage_root r ON r.id = e.root_id
              INNER JOIN members m ON v.m_id = m.m_id
              WHERE
                s.fstype = 'zfs' AND
                vps_deleted IS NULL AND m.m_state = 'active' AND
                vps_backup_enabled = 1 AND (SELECT t_id FROM transactions WHERE t_type = 5006 AND t_done = 0 AND t_vps = vps_id) IS NULL
              ORDER BY v.vps_id")

rs.each_hash do |row|
  param = {
      :src_node_type => :zfs,
      :dst_node_type => :zfs, # FIXME
      :dataset => row["root_dataset"] + "/" + row["dataset"],
      :path => row["root_path"] + "/" + row["path"],
      :backuper => row["backuper_server_id"].to_i,
      :backup_type => :backup_regular,
      :rotate_backups => true,
  }

  if options[:dry_run]
    puts "BACKUP VPS=#{row["vps_id"]}, FROM SERVER=#{row["server_name"]}, TO SERVER=#{row["backuper_server_id"]}, PARAMS=#{param.to_json}"

  else
    t = Transaction.new(db)

    t.queue({
                :node => row["node_id"].to_i,
                :vps => row["vps_id"].to_i,
                :type => :backup_snapshot,
                :param => param,
            })
  end
end
