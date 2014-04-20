module Commands
  class Reload < Command
    description "Reload vpsAdmind's configuration"

    def process
      puts 'Config reloaded'
    end
  end
end
