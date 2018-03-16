module NodeCtl::Commands
  class Resume < NodeCtl::Command
    description 'Resume execution of queued transactions'

    def process
      puts 'Resumed'
    end
  end
end
