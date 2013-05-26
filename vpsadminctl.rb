#!/usr/bin/env ruby

require 'pathname'

$: << File.dirname(Pathname.new(__FILE__).realpath) unless $:.include? File.dirname(__FILE__)

require 'optparse'
require 'lib/rc'

options = {
	:sock => "/var/run/vpsadmind.sock",
	:status => {
		:workers => false,
		:consoles => false,
		:header => true,
	},
	:stop => {
		:force => false,
	},
	:restart => {
		:force => false,
	},
	:kill => {
		:all => false,
		:type => nil,
	}
}

command = ARGV[0]

opt_parser = OptionParser.new do |opts|
	opts.banner = <<END_BANNER
Usage: vpsadminctl <command> [options]

Commands:
    status             Show vpsAdmind's status
    reload             Reload vpsAdmind's configuration
    stop               Safely stop vpsAdmind - wait for all commands to finish
    restart            Safely restart vpsAdmind
    update             Safely stop vpsAdmind, then update by git pull and start again
    kill [ID|TYPE]...  Kill transaction(s) that are being processed
    reinit             Reinitialize firewall chains and rules
    refresh            Update VPS status, traffic counters, storage usage and server status

For specific options type: vpsadminctl <command> --help

END_BANNER

	opts.separator "Specific options:"
	
	case command
	when "status"
		opts.on("-c", "--consoles", "List exported consoles") do
			options[:status][:consoles] = true
		end
		
		opts.on("-w", "--workers", "List workers") do
			options[:status][:workers] = true
		end
		
		opts.on("-H", "--no-header", "Suppress columns header") do
			options[:status][:header] = false
		end
	when "stop"
		opts.on("-f", "--force", "Force stop - kills all transactions that are being processed and exits immediately") do
			options[:stop][:force] = true
		end
	when "restart"
		opts.on("-f", "--force", "Force restart - kills all transactions that are being processed and restarts immediately") do
			options[:restart][:force] = true
		end
	when "kill"
		opts.on("-a", "--all", "Kill all transactions") do
			options[:kill][:all] = true
		end
		opts.on("-t", "--type", "Kill all transactions of this type") do
			options[:kill][:type] = true
		end
	end
	
	opts.separator "Common options:"
	
	opts.on("-s", "--socket [SOCKET]", "Specify socket") do |s|
		options[:sock] = s
	end
	
	opts.on("-v", "--version", "Print version and exit") do
		puts VpsAdminCtl::VERSION
		exit
	end
	
	opts.on_tail("-h", "--help", "Show this message") do
		puts opts
		exit
	end
end

unless ARGV.size > 0
	$stderr.puts "No command specified"
	puts opt_parser
	exit(false)
end

begin
	opt_parser.parse!
rescue OptionParser::InvalidOption
	$stderr.puts $!
	puts opt_parser
	exit(false)
end

rc = VpsAdminCtl::RemoteControl.new(options[:sock])

unless rc.is_valid?(command)
	$stderr.puts "Invalid command"
	puts opt_parser
	exit(false)
end

ret = rc.exec(command, options[command.to_sym])

if ret && ret[:status] == :failed
	$stderr.puts "Command error: #{ret[:error]}"
	exit(false)
end
