#!/usr/bin/env ruby

$: << File.dirname(__FILE__) unless $:.include? File.dirname(__FILE__)

require 'lib/daemon'

require 'optparse'

require 'rubygems'
require 'daemons'

options = {
	:daemonize => false,
}

OptionParser.new do |opts|
	opts.on("-d", "--daemonize", "Run in background") do
		options[:daemonize] = true
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
	})
end

Thread.abort_on_exception = true
vpsAdmind = VpsAdmind::Daemon.new()
vpsAdmind.start
