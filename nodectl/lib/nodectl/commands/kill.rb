module NodeCtl
  class Commands::Kill < Command::Remote
    cmd :kill
    args '[ID|TYPE]...'
    description 'Kill transaction(s) that are being processed'

    def options(parser, args)
      opts.update({
        all: false,
        type: nil,
      })

      parser.on('-a', '--all', 'Kill all transactions') do
        opts[:all] = true
      end

      parser.on('-t', '--type', 'Kill all transactions of this type') do
        opts[:type] = true
      end
    end

    def validate
      if opts[:all]
        params[:transactions] = :all

      elsif opts[:type]
        if args.size < 1
          raise ValidationError, 'missing transaction type(s)'
        end

        params[:types] = args

      else
        if args.size < 1
          raise ValidationError, 'missing transaction id(s)'
        end

        params[:transactions] = args
      end
    end

    def process
      response[:msgs].each do |i, msg|
        puts "#{i}: #{msg}"
      end

      puts '' if response[:msgs].size > 0

      puts "Killed #{response[:killed]} transactions"
    end
  end
end
