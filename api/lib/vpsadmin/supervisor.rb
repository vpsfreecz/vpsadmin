require 'bunny'

module VpsAdmin
  module Supervisor
    module Console ; end
    module Node ; end

    def self.start(cfg)
      connection = Bunny.new(
        hosts: cfg.fetch('hosts'),
        vhost: cfg.fetch('vhost', '/'),
        username: cfg.fetch('username'),
        password: cfg.fetch('password'),
        log_file: STDERR,
      )
      connection.start

      Console::Rpc.start(connection)
      NodeManager.start(connection)
    end
  end
end
