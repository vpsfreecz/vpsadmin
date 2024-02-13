module NodeCtl
  class Commands::Kill < Command::Remote
    cmd :kill
    args '[ID|TYPE]...'
    description 'Kill transaction(s) that are being processed'

    def options(parser, _args)
      opts.update({
                    all: false,
                    type: nil
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
        raise ValidationError, 'missing transaction type(s)' if args.size < 1

        params[:types] = args.map(&:to_i)

      else
        raise ValidationError, 'missing transaction id(s)' if args.size < 1

        params[:transactions] = args.map(&:to_i)
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
