module VpsAdmindCtl::Commands
  class Update < VpsAdmindCtl::Command
    description 'Safely stop vpsAdmind, then update by git pull and start again'

    def options(opts, args)
      @opts = {
          :force => false,
      }

      opts.on('-f', '--force', 'Force update - kills all transactions that are being processed and updates immediately') do
        @opts[:force] = true
      end
    end

    def prepare
      @opts
    end

    def process
      puts 'Update scheduled'
    end
  end
end
