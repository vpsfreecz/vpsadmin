module VpsAdmindCtl::Commands
  class Set < VpsAdmindCtl::Command
    args '<command>'
    description 'Set vpsAdmind resources and properties'

    def options(opts, args)
      opts.separator <<END

Subcommands:
config <some.key=value>...    Change variable in vpsAdmind's configuration
END
    end

    def validate
      raise VpsAdmindCtl::ValidationError.new('missing resource') if @args.size < 2
      raise VpsAdmindCtl::ValidationError.new('missing arguments') if @args.size < 3
    end

    def prepare
      ret = {}

      case @args[1]
        when 'config'
          ret[:config] = []
          @args[2..-1].each do |opt|
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
            ret[:config] << root
          end
      end

      {:resource => @args[1]}.update(ret)
    end

    def process
      puts 'Config changed'
    end
  end
end
