require 'optparse'
require 'nodectl/command'
require 'nodectl/version'

module NodeCtl
  class Cli
    def self.run
      cli = new
      cli.run
    end

    attr_reader :options, :command

    def initialize
      @options = {
        parsable: false,
        sock: '/run/nodectl/nodectld.sock',
      }
    end

    def run
      if ARGV.size >= 1
        cmd = Command.get(ARGV[0].to_sym)
        @command = cmd.new if cmd
      end

      cli = opt_parser

      if ARGV.size <= 0
        warn 'No command specified'
        warn cli
        exit(false)
      end

      begin
        cli.parse!

      rescue OptionParser::InvalidOption => e
        warn e.message
        warn cli
        exit(false)
      end

      if command.nil?
        warn "Command '#{ARGV[0]}' not recognized"
        warn cli
        exit(false)
      end

      command.global_opts = options
      command.args = ARGV[1..-1]

      begin
        command.validate

      rescue ValidationError => e
        warn 'Command failed'
        warn "#{command.cmd}: #{e.message}"
        exit(false)

      rescue => e
        warn 'Command failed'
        warn e.inspect
        exit(false)
      end

      ret = command.execute

      if ret.is_a?(Hash) && !ret[:status]
        warn "Command error: #{ret[:message]}"
        exit(false)
      end
    end

    protected
    def opt_parser
      OptionParser.new do |opts|
        opts.banner = <<END_BANNER
Usage: nodectl <command> [global options] [command options]

Commands:
END_BANNER

        Command.all.each do |c|
          opts.banner << sprintf("%-20s %s\n", c.label, c.description)
        end

        opts.banner << <<END_BANNER

For specific options type: nodectl <command> --help

END_BANNER

        if command
          opts.separator 'Command-specific options:'
          command.options(opts, ARGV[1..-1])
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
          puts NodeCtl::VERSION
          exit
        end

        opts.on_tail('-h', '--help', 'Show this message') do
          puts opts
          exit
        end
      end
    end
  end
end
