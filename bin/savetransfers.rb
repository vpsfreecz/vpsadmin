#!/usr/bin/env ruby

require 'pathname'
require File.join(File.dirname(Pathname.new(__FILE__).realpath), '..', 'lib/vpsadmind')

require 'optparse'

options = {
    :config => '/etc/vpsadmin/vpsadmind.yml',
    :older => 60,
}

OptionParser.new do |opts|
  opts.on('-c', '--config [CONFIG FILE]', 'Config file') do |cfg|
    options[:config] = cfg
  end

  opts.on('-o', '--older-than [SECONDS]', Integer, 'Move transfers older than SECONDS') do |cfg|
    options[:older] = cfg || 60
  end

  opts.on_tail('-h', '--help', 'Show this message') do
    puts opts
    exit
  end
end.parse!

$CFG = VpsAdmind::AppConfig.new(options[:config])

unless $CFG.load
  exit(false)
end

db = VpsAdmind::Db.new

db.transaction do |t|
  t.query("
          INSERT INTO ip_traffics (
            ip_address_id, user_id, protocol, role,
            packets_in, packets_out, bytes_in, bytes_out,
            created_at
          )

          SELECT
            ip_address_id, user_id, protocol, role,
            SUM(packets_in) AS spi, SUM(packets_out) AS spo,
            SUM(bytes_in) AS sbi, SUM(bytes_out) AS sbo,
            DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00')
          FROM `ip_recent_traffics` r
          WHERE created_at < DATE_SUB(NOW(), INTERVAL 60 SECOND)
          GROUP BY ip_address_id,
                   user_id,
                   protocol,
                   role,
                   DATE_FORMAT(created_at, '%Y-%m-%d %H:00:00')

          ON DUPLICATE KEY UPDATE packets_in = packets_in + values(packets_in),
                                  packets_out = packets_out + values(packets_out),
                                  bytes_in = bytes_in + values(bytes_in),
                                  bytes_out = bytes_out + values(bytes_out)
          ")
  t.query('DELETE FROM ip_recent_traffics WHERE created_at < DATE_SUB(NOW(), INTERVAL 60 SECOND)')
end
