#!/usr/bin/env ruby

path = File.join(File.dirname(__FILE__), '..')
$: << path unless $:.include?(path)

require 'lib/vpsadmind'

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

$CFG = AppConfig.new(options[:config])

unless $CFG.load
  exit(false)
end

db = Db.new

db.transaction do |t|
  t.query("
          INSERT INTO transfered (tr_ip, tr_proto, tr_packets_in, tr_packets_out, tr_bytes_in, tr_bytes_out, tr_date)

          SELECT
            tr_ip, tr_proto, SUM(tr_packets_in) AS spi,
            SUM(tr_packets_out) AS spo, SUM(tr_bytes_in) AS sbi,
            SUM(tr_bytes_out) AS sbo, DATE_FORMAT(tr_date, '%Y-%m-%d %H:00:00')
          FROM `transfered_recent` r
          WHERE tr_date < DATE_SUB(NOW(), INTERVAL 60 SECOND)
          GROUP BY tr_ip, tr_proto, DATE_FORMAT(tr_date, '%Y-%m-%d %H:00:00')

          ON DUPLICATE KEY UPDATE tr_packets_in = tr_packets_in + values(tr_packets_in),
                                  tr_packets_out = tr_packets_out + values(tr_packets_out),
                                  tr_bytes_in = tr_bytes_in + values(tr_bytes_in),
                                  tr_bytes_out = tr_bytes_out + values(tr_bytes_out)
          ")
  t.query('DELETE FROM transfered_recent WHERE tr_date < DATE_SUB(NOW(), INTERVAL 60 SECOND)')
end
