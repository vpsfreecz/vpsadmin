module VpsAdmindCtl::Commands
  class Resume < VpsAdmindCtl::Command
    description 'Resume execution of queued transactions'

    def process
      puts 'Resumed'
    end
  end
end
