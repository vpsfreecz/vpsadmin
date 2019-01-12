module VpsAdmindCtl::Commands
  class Kill < VpsAdmindCtl::Command
    args '[ID|TYPE]...'
    description 'Kill command(s) that are being executed'

    def options(parser, args)
      opts.update({
        all: false,
        type: nil,
      })

      parser.on('-a', '--all', 'Kill all commands') do
        opts[:all] = true
      end

      parser.on('-t', '--type', 'Kill all commands of this type') do
        opts[:type] = true
      end
    end

    def validate
      if opts[:all]
        params[:commands] = :all

      elsif opts[:type]
        if args.size < 1
          raise ValidationError, 'missing command type(s)'
        end

        params[:types] = args

      else
        if args.size < 1
          raise ValidationError, 'missing command id(s)'
        end

        params[:commands] = args
      end
    end

    def process
      response[:msgs].each do |i, msg|
        puts "#{i}: #{msg}"
      end

      puts '' if response[:msgs].size > 0

      puts "Killed #{response[:killed]} commands"
    end
  end
end
