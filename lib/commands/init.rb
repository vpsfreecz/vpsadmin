module Commands
  class Init < CommandTemplates::ResourceControl
    description 'Initialize resource'

    def process
      puts 'Initialized'
      super
    end
  end
end
