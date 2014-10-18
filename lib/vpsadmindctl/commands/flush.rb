module VpsAdmindCtl::Commands
  class Flush < VpsAdmindCtl::CommandTemplates::ResourceControl
    description 'Flush resource'

    def process
      puts 'Flushed'
      super
    end
  end
end
