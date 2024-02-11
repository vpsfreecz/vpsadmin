require 'haveapi/client'

module VpsAdmin
  module Client
    class Client < HaveAPI::Client::Client
    end

    # Shortcut to {VpsAdmin::Client::Client.new}
    def self.new(*args)
      Client.new(*args)
    end
  end
end
