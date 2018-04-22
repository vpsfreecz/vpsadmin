module NodeCtl
  class Commands::Restart < Command::Remote
    cmd :restart
    description 'Safely restart nodectld'

    def options(parser, args)
      opts[:force] = false

      parser.on(
        '-f', '--force',
        'Force restart - kills all transactions that are being processed '+
        'and restarts immediately'
      ) do
        opts[:force] = true
      end
    end

    def validate
      params[:force] = opts[:force]
    end

    def process
      puts 'Restart scheduled'
    end
  end
end
