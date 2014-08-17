module Commands
  class Flush < CommandTemplates::ResourceControl
    description 'Flush resource'

    def process
      puts 'Flushed'
      super
    end
  end
end
