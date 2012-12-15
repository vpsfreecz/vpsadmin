#!/usr/bin/env ruby

$: << File.dirname(__FILE__) unless $:.include? File.dirname(__FILE__)

require 'lib/config'
require 'lib/daemon'

require 'optparse'

require 'rubygems'
require 'daemons'

options = {
	:init => false,
	:config => "/etc/vpsadmin/vpsadmind.yml",
	:daemonize => false,
	:export_console => false,
	:logdir => "/var/log",
	:piddir => "/var/run",
}

OptionParser.new do |opts|
	opts.on("-i", "--init", "Init firewall rules") do
		options[:init] = true
	end
	
	opts.on("-c", "--config [CONFIG FILE]", "Config file") do |cfg|
		options[:config] = cfg
	end
	
	opts.on("-e", "--export-console", "Export VPS consoles via socket") do
		options[:export_console] = true
	end
	
	opts.on("-d", "--daemonize", "Run in background") do
		options[:daemonize] = true
	end
	
	opts.on("-l", "--logdir [LOG DIR]", "Log dir") do |log|
		parts = log.split(File::SEPARATOR)
		options[:logdir] = log
	end
	
	opts.on("p", "--pidfile [PID FILE]", "PID file") do |pid|
		parts = pid.split(File::SEPARATOR)
		options[:piddir] = parts.slice(0, parts.count-1).join(File::SEPARATOR)
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
end.parse!

if options[:daemonize]
	Daemons.daemonize({
		:app_name => "vpsadmind",
		:log_output => true,
		:log_dir => options[:logdir],
		:dir_mode => :normal,
		:dir => options[:piddir],
	})
end

Dir.chdir("/opt/vpsadmind")

load_cfg(options[:config])

Thread.abort_on_exception = true
vpsAdmind = VpsAdmind::Daemon.new()
vpsAdmind.init if options[:init]
vpsAdmind.export_console if options[:export_console]
vpsAdmind.start
