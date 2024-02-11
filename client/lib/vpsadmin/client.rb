require 'haveapi/client'

module VpsAdmin
  module Client
    class Client < HaveAPI::Client::Client
    end

    # Shortcut to {VpsAdmin::Client::Client.new}
    def self.new(*)
      Client.new(*)
    end
  end
end
