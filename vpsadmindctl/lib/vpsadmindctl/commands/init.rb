module VpsAdmindCtl::Commands
  class Init < VpsAdmindCtl::CommandTemplates::ResourceControl
    description 'Initialize resource'

    def process
      puts 'Initialized'
      super
    end
  end
end
