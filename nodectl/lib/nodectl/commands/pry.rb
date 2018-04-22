require 'pry-remote'

module NodeCtl
  class Commands::Pry < Command::Remote
    cmd :pry
    description 'Open remote console'

    def execute
      @client = Client.new(global_opts[:sock])

      begin
        client.open
        client.cmd(cmd, params)
        sleep(1)
        PryRemote::CLI.new.run

      rescue => e
        warn "Error occured: #{e.message}"
        warn 'Are you sure that nodectld is running and configured properly?'
        return error('Cannot connect to nodectld')
      end

      puts "\nSession closed"
    end
  end
end
