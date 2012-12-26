#!/usr/bin/env ruby

require 'pathname'

$: << File.dirname(Pathname.new(__FILE__).realpath) unless $:.include? File.dirname(__FILE__)

require 'optparse'
require 'lib/rc'

options = {
	:sock => "/var/run/vpsadmind.sock",
	:status => {
		:all => true,
	}
}

unless ARGV.size > 0
	$stderr.puts "Missing action"
	exit(false)
end

rc = VpsAdminCtl::RemoteControl.new(options[:sock])
action = ARGV[0]

unless rc.is_valid?(action)
	$stderr.puts "Invalid action"
	exit(false)
end

OptionParser.new do |opts|
	case action
	when "status"
		opts.on("-a", "--all", "Display all") do
			options[:status][:all] = true
		end
	end
	
	opts.on("-s", "--socket [SOCKET]", "Specify socket") do |s|
		options[:sock] = s
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
end.parse!

ret = rc.exec(action)

if ret && ret[:status] == :failed
	$stderr.puts "Command error: #{ret["error"]}"
	exit(false)
end
