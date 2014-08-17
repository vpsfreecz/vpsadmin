module Commands
  class Pry < Command
    description 'Open remote console'

    def post_send
      sleep(1)
      PryRemote::CLI.new.run
    end

    def process
      puts "\nSession closed"
    end
  end
end
