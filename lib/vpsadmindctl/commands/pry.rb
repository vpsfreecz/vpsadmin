module VpsAdmindCtl::Commands
  class Pry < VpsAdmindCtl::Command
    description 'Open remote console'

    def validate
      unless RUBY_VERSION >= '2.0'
        raise VpsAdmindCtl::ValidationError, 'Pry requires ruby interpreter >= 2.0'
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
