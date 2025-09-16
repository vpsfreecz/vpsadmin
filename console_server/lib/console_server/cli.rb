require 'console_server'
require 'optparse'

module ConsoleServer
  class Cli
    def self.run
      new.run
    end

    def run
      options = parse_options
      Control.run(options[:state_dir])
    end

    protected

    def parse_options
      options = {
        state_dir: '/run/console-server'
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: #{$0} [options]"

        opts.on('-d', '--state-dir DIR', 'Path to state directory') do |v|
          options[:state_dir] = v
        end
      end

      args = parser.parse!

      if args.any?
        warn 'Too many arguments'
        warn parser
        exit(false)
      end

      options
    end
  end
end
