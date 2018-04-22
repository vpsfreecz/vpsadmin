module NodeCtl
  class Commands::Ping < Command::Remote
    cmd :ping
    description 'Check if nodectld is alive'

    def process
      if response[:pong] == 'pong'
        puts 'pong'

      else
        error('nodectld did not respond correctly')
      end
    end
  end
end
