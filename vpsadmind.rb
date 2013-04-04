#!/usr/bin/env ruby

$: << File.dirname(__FILE__) unless $:.include? File.dirname(__FILE__)

require 'lib/config'
require 'lib/daemon'
require 'lib/utils/common'

require 'optparse'

require 'rubygems'
require 'daemons'

options = {
	:config => "/etc/vpsadmin/vpsadmind.yml",
	:daemonize => false,
	:check => false,
	:export_console => false,
	:logdir => "/var/log",
	:piddir => "/var/run",
	:remote => false,
	:wrapper => true,
}

OptionParser.new do |opts|
	opts.on("-c", "--config [CONFIG FILE]", "Config file") do |cfg|
		options[:config] = cfg
	end
	
	opts.on("-e", "--export-console", "Export VPS consoles via socket") do
		options[:export_console] = true
	end
	
	opts.on("-d", "--daemonize", "Run in background") do
		options[:daemonize] = true
	end
	
	opts.on("-k", "--check", "Check config file syntax") do
		options[:check] = true
	end
	
	opts.on("-l", "--logdir [LOG DIR]", "Log dir") do |log|
		parts = log.split(File::SEPARATOR)
		options[:logdir] = log
	end
	
	opts.on("-p", "--pidfile [PID FILE]", "PID file") do |pid|
		parts = pid.split(File::SEPARATOR)
		options[:piddir] = parts.slice(0, parts.count-1).join(File::SEPARATOR)
	end
	
	opts.on("-r", "--remote-control", "Enable remote control") do
		options[:remote] = true
	end
	
	opts.on("-w", "--no-wrapper", "Do not run script in wrapper - auto restart won't work") do
		options[:wrapper] = false
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
end.parse!

if options[:check]
	c = AppConfig.new(options[:config])
	puts "Config seems ok" if c.load
	exit
end

executable = File.expand_path($0)

$CFG = AppConfig.new(options[:config])

unless $CFG.load
	exit(false)
end

if options[:daemonize]
	Daemons.daemonize({
		:app_name => "vpsadmind",
		:log_output => true,
		:log_dir => options[:logdir],
		:dir_mode => :normal,
		:dir => options[:piddir],
	})
end

Dir.chdir($CFG.get(:vpsadmin, :root))

if options[:wrapper]
	log "vpsAdmind wrapper starting"
	
	loop do
		p = IO.popen("exec #{executable} --no-wrapper --config #{options[:config]} #{"--export-console" if options[:export_console]} #{"--remote-control" if options[:remote]} 2>&1")
		
		Signal.trap("TERM") do
			log "Killing daemon"
			Process.kill("TERM", p.pid)
			exit
		end
		
		Signal.trap("HUP") do
			Process.kill("HUP", p.pid)
		end
		
		p.each do |line|
			puts line
		end
		
		# Sets $?
		Process.waitpid(p.pid)
		
		case $?.exitstatus
		when VpsAdmind::EXIT_OK
			log "Stopping daemon"
			exit
		when VpsAdmind::EXIT_STOP
			log "Stopping daemon"
			exit
		when VpsAdmind::EXIT_RESTART
			log "Restarting daemon"
			next
		when VpsAdmind::EXIT_UPDATE
			log "Updating daemon"
			
			g = ""
			
			IO.popen("#{$CFG.get(:bin, :git)} pull 2>&1") do |io|
				g = io.read
			end
			
			if $?.exitstatus == 0
				next
			else
				log "Update failed, git says:"
				puts g
				log "Exiting"
				exit(false)
			end
		else
			log "Daemon crashed with exit status #{$?.exitstatus}"
			exit(false)
		end
	end
end

Signal.trap("HUP") do
	log "Reloading config"
	$CFG.reload
end

log "vpsAdmind starting"

Thread.abort_on_exception = true
vpsAdmind = VpsAdmind::Daemon.new()
vpsAdmind.init if $CFG.get(:vpsadmin, :init)
vpsAdmind.start_em(options[:export_console], options[:remote]) if options[:export_console] || options[:remote]
vpsAdmind.start
