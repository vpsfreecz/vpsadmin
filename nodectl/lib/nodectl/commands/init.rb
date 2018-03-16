module NodeCtl::Commands
  class Init < NodeCtl::CommandTemplates::ResourceControl
    description 'Initialize resource'

    def process
      puts 'Initialized'
      super
    end
  end
end
