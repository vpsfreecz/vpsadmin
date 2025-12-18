require 'bunny'

module VpsAdmin
  module Supervisor
    module Console; end
    module Node; end
    module Vnc; end

    def self.start(cfg)
      connection = Bunny.new(
        hosts: cfg.fetch('hosts'),
        vhost: cfg.fetch('vhost', '/'),
        username: cfg.fetch('username'),
        password: cfg.fetch('password'),
        log_file: $stderr
      )
      connection.start

      Console::Rpc.start(connection)
      Vnc::Rpc.start(connection)
      NodeManager.start(connection)
    end
  end
end
