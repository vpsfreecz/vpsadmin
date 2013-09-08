#!/usr/bin/env ruby

$: << File.dirname(__FILE__) unless $:.include? File.dirname(__FILE__)

require 'lib/config'
require 'lib/db'
require 'lib/transaction'

require 'optparse'
require 'erb'

options = {
	:config => "/etc/vpsadmin/vpsadmind.yml",
	:verbose => false,
}

OptionParser.new do |opts|
	opts.on("-c", "--config [CONFIG FILE]", "Config file") do |cfg|
		options[:config] = cfg
	end
	
	opts.on("-v", "--verbose", "Verbose") do |v|
		options[:verbose] = v
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

Dir.chdir($CFG.get(:vpsadmin, :root))

$db = Db.new

def trans_stat(done = nil, success = nil)
	q = "SELECT COUNT(*) AS cnt
	     FROM transactions
	     WHERE FROM_UNIXTIME(t_time) > DATE_SUB(NOW(), INTERVAL 1 DAY)"
	args = [done, success]
	args.delete_if { |v| v.nil? }
	
	q += " AND t_done = ?" unless done.nil?
	q += " AND t_success = ?" unless success.nil?
	
	st = $db.prepared_st(q, *args)
	ret = st.fetch[0]
	st.close
	ret
end

def url(page, params = nil)
	"http://vpsadmin.vpsfree.cz/?page=#{page}#{params ? "&#{params}" : ""}"
end

def time(t)
	Time.at(t).strftime("%Y-%m-%d %H:%M:%S")
end

def duration(interval)
	d = interval / 86400
	h = interval / 3600 % 24
	m = interval / 60 % 60
	s = interval % 60
	
	if d > 0
		"%d days, %02d:%02d:%02d" % [d, h, m, s]
	else
		"%02d:%02d:%02d" % [h, m, s]
	end
end

def balance(a, b)
	ret = a - b
	sign = ""
	
	if ret > 0
		sign = "+"
	elsif ret < 0
		sign = "-"
	end
	
	"#{sign}#{ret}"
end

date_start = (Time.new - 24*60*60).strftime("%Y-%m-%d %H:%M")
date_end = Time.new.strftime("%Y-%m-%d %H:%M")

m_new = $db.query("SELECT m.*, (SELECT COUNT(*) FROM vps v WHERE v.m_id = m.m_id) AS vps_cnt
                  FROM members m
                  WHERE m_created > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 DAY))
                  ORDER BY m_id")
m_deleted = $db.query("SELECT m.*, (SELECT COUNT(*) FROM vps v WHERE v.m_id = m.m_id) AS vps_cnt
                      FROM members m
                      WHERE m_deleted > UNIX_TIMESTAMP(DATE_SUB(NOW(), INTERVAL 1 DAY)) AND m_state = 'deleted'
                      ORDER BY m_id")

failed_transactions = $db.query("SELECT t.*, m.m_nick, s.server_name FROM transactions t
                               LEFT JOIN members m ON t_m_id = m_id
                               LEFT JOIN servers s ON t_server = server_id
                               WHERE FROM_UNIXTIME(t_time) > DATE_SUB(NOW(), INTERVAL 1 DAY) AND t_done = 1 AND t_success != 1
                               ORDER BY t_id DESC")
report = ERB.new(File.new("templates/daily_report.erb").read, 0).result(binding)

dest = $db.query("SELECT cfg_value FROM sysconfig WHERE cfg_name = 'mailer_daily_report_sendto'").fetch_row[0].gsub("\"", "").split(",")

node = nil

begin
	node = $db.query("SELECT server_id FROM servers WHERE server_type = 'mailer' ORDER BY server_id LIMIT 1").fetch_row[0].to_i
rescue NoMethodError
	$stderr.puts "No mailer available"
	exit(false)
end

if options[:verbose]
	puts "Send to:"
	p dest
	puts report
end

t = Transaction.new($db)
t.queue({
	:node => node,
	:vps => nil,
	:type => :send_mail,
	:depends => nil,
	:param => {
		:to => dest.first,
		:subject => "vpsAdmin daily report #{Time.new.strftime("%d/%m/%Y")}",
		:msg => report,
		:cc => [],
		:bcc => dest[1..-1],
		:html => true,
	}
})
