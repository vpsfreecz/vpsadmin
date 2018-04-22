module NodeCtl
  class Commands::Reinit < CommandTemplates::ResourceControl
    cmd :reinit
    description 'Reinitialize resource'

    def process
      puts 'Reinitialized'
      super
    end
  end
end
