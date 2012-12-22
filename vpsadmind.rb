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
	:wrapper => true,
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
	
	opts.on("-w", "--no-wrapper", "Do not run script in wrapper - auto restart won't work") do
		options[:wrapper] = false
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
end.parse!

executable = File.expand_path($0)
load_cfg(options[:config])

if options[:daemonize]
	Daemons.daemonize({
		:app_name => "vpsadmind",
		:log_output => true,
		:log_dir => options[:logdir],
		:dir_mode => :normal,
		:dir => options[:piddir],
	})
end

Dir.chdir($APP_CONFIG[:vpsadmin][:root])

if options[:wrapper]
	loop do
		p = IO.popen("exec #{executable} --no-wrapper --config #{options[:config]} #{"--init" if options[:init]} #{"--export-console" if options[:export_console]} 2>&1")
		
		Signal.trap("TERM") do
			puts "Killing daemon"
			Process.kill("TERM", p.pid)
			exit
		end
		
		Signal.trap("HUP") do
			Process.kill("HUP", p.pid)
		end
		
		puts p.read
		Process.waitpid(p.pid)
		
		case $?.exitstatus
		when VpsAdmind::EXIT_OK
			exit
		when VpsAdmind::EXIT_RESTART
			next
		when VpsAdmind::EXIT_UPDATE
			load_cfg(options[:config])
			
			IO.popen("#{$APP_CONFIG[:bin][:git]} pull 2>&1") do |io|
				g = io.read
			end
			
			if $? == 0
				next
			else
				exit(false)
			end
		else
			exit(false)
		end
	end
end

Signal.trap("HUP") do
	puts "Reloading config..."
	reload_cfg(options[:config])
end

Thread.abort_on_exception = true
vpsAdmind = VpsAdmind::Daemon.new()
vpsAdmind.init if options[:init]
vpsAdmind.export_console if options[:export_console]
vpsAdmind.start
