module VpsAdmindCtl::Commands
  class Reinit < VpsAdmindCtl::CommandTemplates::ResourceControl
    description 'Reinitialize resource'
    def process
      puts 'Reinitialized'
      super
    end
  end
end
