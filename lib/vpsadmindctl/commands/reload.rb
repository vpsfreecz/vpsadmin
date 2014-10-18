module VpsAdmindCtl::Commands
  class Reload < VpsAdmindCtl::Command
    description "Reload vpsAdmind's configuration"

    def process
      puts 'Config reloaded'
    end
  end
end
