module NodeCtl::Commands
  class Reload < NodeCtl::Command
    description "Reload nodectld's configuration"

    def process
      puts 'Config reloaded'
    end
  end
end
