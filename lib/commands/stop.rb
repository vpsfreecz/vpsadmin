module Commands
  class Stop < Command
    description 'Safely stop vpsAdmind'

    def options(opts, args)
      @opts = {
          :force => false,
      }

      opts.on('-f', '--force', 'Force stop - kills all transactions that are being processed and restarts immediately') do
        @opts[:force] = true
      end
    end

    def prepare
      {:force => @opts[:force]}
    end

    def process
      puts 'Stop scheduled'
    end
  end
end
