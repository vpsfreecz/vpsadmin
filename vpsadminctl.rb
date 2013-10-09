#!/usr/bin/env ruby

require 'pathname'

$: << File.dirname(Pathname.new(__FILE__).realpath) unless $:.include? File.dirname(__FILE__)

require 'optparse'
require 'lib/rc'

options = {
	:parsable => false,
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
	},
	:install => {
		:id => nil,
		:name => nil,
		:role => :node,
		:location => nil,
		:addr => nil,
		# node
		:maxvps => 30,
		:ve_private => "/vz",
		:fstype => "ext4",
		# storage
		# mailer
		# end
		:create => true,
		:propagate => false,
		:gen_configs => false,
		:ssh_key => false,
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
    install            Add node to cluster, save public key to DB, generate configs

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
	when "install"
		opts.on("--id ID", Integer, "Node ID") do |id|
			options[:install][:id] = id
		end
		
		opts.on("--name NAME", "Node name") do |name|
			options[:install][:name] = name
		end
		
		opts.on("--role TYPE", [:node, :storage, :mailer], "Node type (node, storage or mailer)") do |t|
			options[:install][:role] = t
		end
		
		opts.on("--location LOCATION", "Node location, might be id or label") do |l|
			options[:install][:location] = l
		end
		
		opts.on("--addr ADDR", "Node IP address") do |addr|
			options[:install][:addr] = addr
		end
		
		opts.on("--[no-]create", "Update only server public key and/or generate configs, do not create node") do |i|
			options[:install][:create] = i
		end
		
		opts.on("--[no-]propagate", "Regenerate known_hosts on all nodes") do |p|
			options[:install][:propagate] = p
		end
		
		opts.on("--[no-]generate-configs", "Generate configs on this node") do |g|
			options[:install][:gen_configs] = g
		end
		
		opts.on("--[no-]ssh-key", "Handle SSH key and authorized_keys") do |k|
			options[:install][:ssh_key] = k
		end
		
		opts.separator ""
		opts.separator "Options for role NODE:"
		
		opts.on("--maxvps CNT", Integer, "Max number of VPS") do |m|
			options[:install][:maxvps] = m
		end
		
		opts.on("--ve-private PATH", "Path to VE_PRIVATE, expands variable %{veid}") do |p|
			options[:install][:ve_private] = p
		end
		
		opts.on("--fstype FSTYPE", [:ext4, :zfs, :zfs_compat], "Select FS type (ext4, zfs, zfs_compat)") do |fs|
			options[:install][:fstype] = fs
		end
	end
	
	opts.separator ""
	opts.separator "Common options:"
	
	opts.on("-p", "--parsable", "Use in scripts, output can be easily parsed") do
		options[:parsable] = true
	end
	
	opts.on("-s", "--socket SOCKET", "Specify socket") do |s|
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

rc = VpsAdminCtl::RemoteControl.new(options)

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
