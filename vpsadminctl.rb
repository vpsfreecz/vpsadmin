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
	$stderr.puts "No command specified"
	exit(false)
end

rc = VpsAdminCtl::RemoteControl.new(options[:sock])
command = ARGV[0]

OptionParser.new do |opts|
	opts.banner = <<END_BANNER
Usage: vpsadminctl <command> [options]

Commands:
    status      Show vpsAdmind's status
    reload      Reload vpsAdmind's configuration (currently only thread count)
    stop        Safely stop vpsAdmind - wait for all commands to finish
    restart     Safely restart vpsAdmind
    update      Safely stop vpsAdmind, then update by git pull and start again

END_BANNER

	opts.separator "Specific options:"
	
	case command
	when "status"
		opts.on("-a", "--all", "Display all") do
			options[:status][:all] = true
		end
	end
	
	opts.separator "Common options:"
	
	opts.on("-s", "--socket [SOCKET]", "Specify socket") do |s|
		options[:sock] = s
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
end.parse!

unless rc.is_valid?(command)
	$stderr.puts "Invalid command"
	exit(false)
end

ret = rc.exec(command)

if ret && ret[:status] == :failed
	$stderr.puts "Command error: #{ret["error"]}"
	exit(false)
end
