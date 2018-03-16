module NodeCtl::Commands
  class Restart < NodeCtl::Command
    description 'Safely restart nodectld'

    def options(opts, args)
      @opts = {
          :force => false,
      }

      opts.on('-f', '--force', 'Force restart - kills all transactions that are being processed and restarts immediately') do
        @opts[:force] = true
      end
    end

    def prepare
      {:force => @opts[:force]}
    end

    def process
      puts 'Restart scheduled'
    end
  end
end
