module NodeCtl::Commands
  class Flush < NodeCtl::CommandTemplates::ResourceControl
    description 'Flush resource'

    def process
      puts 'Flushed'
      super
    end
  end
end
