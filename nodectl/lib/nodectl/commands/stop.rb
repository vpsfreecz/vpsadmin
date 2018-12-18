module NodeCtl
  class Commands::Stop < Command::Remote
    cmd :stop
    description 'Safely stop nodectld'

    def options(parser, args)
      opts[:force] = false

      parser.on(
        '-f', '--force',
        'Force stop - kills all transactions that are being processed '+
        'and restarts immediately'
      ) do
        opts[:force] = true
      end
    end

    def validate
      params[:force] = opts[:force]
    end

    def process
      puts 'Stop scheduled'
    end
  end
end
