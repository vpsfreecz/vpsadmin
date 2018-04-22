module NodeCtl
  class Commands::Script < Command::Local
    cmd :script
    args '<file>'
    description 'Run ruby script with libnodectld and nodectl in path'

    def validate
      raise ValidationError, 'missing script name' if args.size < 1
      raise ValidationError, 'too many arguments' if args.size > 1
    end

    def execute
      load(args[0])
    end
  end
end
