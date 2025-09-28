module NodeCtl
  class Commands::Script < Command::Local
    cmd :script
    args '<file> [arguments...]'
    description 'Run ruby script with libnodectld and nodectl in path'

    def validate
      raise ValidationError, 'missing script name' if args.empty?
    end

    def execute
      script = args[0]

      ARGV.shift # script
      ARGV.shift # <file>

      load(script)
    end
  end
end
