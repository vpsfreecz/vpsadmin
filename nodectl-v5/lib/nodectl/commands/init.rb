module NodeCtl
  class Commands::Init < CommandTemplates::ResourceControl
    cmd :init
    description 'Initialize resource'

    def process
      puts 'Initialized'
      super
    end
  end
end
