#!/usr/bin/env ruby

require 'pathname'

$: << File.dirname(Pathname.new(__FILE__).realpath) unless $:.include? File.dirname(__FILE__)

require 'optparse'
require 'lib/rc'

options = {
	:parsable => false,
	:sock => '/var/run/vpsadmind.sock',
}

command = nil

opt_parser = OptionParser.new do |opts|
	opts.banner = <<END_BANNER
Usage: vpsadmindctl <command> [global options] [command options]

Commands:
END_BANNER

  Command.all do |c|
    opts.banner += sprintf("%-20s %s\n", c.label, c.description)
  end

  opts.banner += <<END_BANNER

For specific options type: vpsadmindctl <command> --help

END_BANNER

  unless ARGV[0].nil?
    klass = Command.get(ARGV[0])

    if klass
      command = klass.new
      opts.separator 'Specific options:'

      command.options(opts, ARGV[1..-1])
    end
  end
	
	opts.separator ''
	opts.separator 'Global options:'
	
	opts.on('-p', '--parsable', 'Use in scripts, output can be easily parsed') do
		options[:parsable] = true
	end
	
	opts.on('-s', '--socket SOCKET', 'Specify socket') do |s|
		options[:sock] = s
	end
	
	opts.on('-v', '--version', 'Print version and exit') do
		puts VpsAdmindCtl::VERSION
		exit
	end
	
	opts.on_tail('-h', '--help', 'Show this message') do
		puts opts
		exit
	end
end

unless ARGV.size > 0
	$stderr.puts 'No command specified'
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

rc = VpsAdmindCtl::RemoteControl.new(options)

unless command
	$stderr.puts 'Invalid command'
	puts opt_parser
	exit(false)
end

ret = rc.exec(command)

if ret && ret[:status] == :failed
	$stderr.puts "Command error: #{ret[:error]}"
	exit(false)
end
