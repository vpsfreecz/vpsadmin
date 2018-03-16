module NodeCtl::Commands
  class Reinit < NodeCtl::CommandTemplates::ResourceControl
    description 'Reinitialize resource'
    def process
      puts 'Reinitialized'
      super
    end
  end
end
