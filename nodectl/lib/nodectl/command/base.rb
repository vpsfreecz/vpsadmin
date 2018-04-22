module NodeCtl
  class Command::Base
    class << self
      # Set/get command name
      def cmd(n = nil)
        if n
          @cmd = n
          Command.register(n, self)

        elsif @cmd
          @cmd
        end
      end

      # Set/get command description
      def description(desc = nil)
        if desc
          @description = desc
        else
          @description
        end
      end

      # Set/get command arguments description
      def args(text = nil)
        if text
          @args = text
        else
          @args
        end
      end

      # Set/get command label
      def label
        "#{cmd} #{args}"
      end

      def run

      end

      def inherited(subclass)
        subclass.args(@args)
      end
    end

    # @param [Hash] command-specific options
    # @return [Hash]
    attr_accessor :opts

    # @param [Hash] global options
    # @return [Hash]
    attr_accessor :global_opts

    # @param [Array<String>] command-specific command-line arguments
    # @return [Array<String>]
    attr_accessor :args

    def initialize
      @opts = {}
      @global_opts = {}
    end

    # Add command-specific CLI options to `opts`
    # @param parser [OptionParser]
    # @param args [Array<String>]
    def options(parser, args)
      # No options by default
    end

    # Validate command-line options and arguments
    def validate

    end

    # Execute command
    def execute

    end

    # Command name
    # @return [Symbol]
    def cmd
      self.class.cmd
    end

    protected
    def ok
      {status: true}
    end

    def error(msg)
      {status: false, message: msg}
    end
  end
end
