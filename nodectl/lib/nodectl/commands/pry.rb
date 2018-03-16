module NodeCtl::Commands
  class Pry < NodeCtl::Command
    description 'Open remote console'

    def validate
      unless RUBY_VERSION >= '2.0'
        raise NodeCtl::ValidationError, 'Pry requires ruby interpreter >= 2.0'
      end
    end

    def post_send
      sleep(1)
      PryRemote::CLI.new.run
    end

    def process
      puts "\nSession closed"
    end
  end
end
