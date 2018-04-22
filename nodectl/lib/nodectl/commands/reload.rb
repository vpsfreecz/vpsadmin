module NodeCtl
  class Commands::Reload < Command::Remote
    cmd :reload
    description "Reload nodectld's configuration"

    def process
      puts 'Config reloaded'
    end
  end
end
