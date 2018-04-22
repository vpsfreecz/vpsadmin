module NodeCtl
  class Commands::Set < Command::Remote
    cmd :set
    args '<command>'
    description 'Set nodectld resources and properties'

    def options(parser, args)
      parser.separator <<END

Subcommands:
config <some.key=value>...    Change variable in nodectld's configuration
END
    end

    def validate
      raise ValidationError, 'missing resource' if args.size < 1
      raise ValidationError, 'missing arguments' if args.size < 2

      case args[0]
      when 'config'
        params[:config] = []

        args[1..-1].each do |opt|
          key, val = opt.split('=')
          root = {}
          tmp = root

          parts = key.split('.')
          parts[0..-2].each do |part|
            tmp[part] = {}
            tmp = tmp[part]
          end

          if val =~ /^\d+$/
            tmp[parts.last] = val.to_i
          else
            tmp[parts.last] = val
          end

          params[:config] << root
        end
      end

      params[:resource] = args[0]
    end

    def process
      puts 'Config changed'
    end
  end
end
