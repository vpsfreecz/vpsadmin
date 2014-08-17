module Commands
  class Reinit < CommandTemplates::ResourceControl
    description 'Reinitialize resource'
    def process
      puts 'Reinitialized'
      super
    end
  end
end
