module NodeCtl::Commands
  class Ping < NodeCtl::Command
    description 'Check if nodectld is alive'

    def process
      if @res[:pong] == 'pong'
        puts 'pong'

      else
        {status: :failed, error: 'nodectld did not respond correctly'}
      end
    end
  end
end
