module NodeCtl
  class Commands::Flush < CommandTemplates::ResourceControl
    cmd :flush
    description 'Flush resource'

    def process
      puts 'Flushed'
      super
    end
  end
end
