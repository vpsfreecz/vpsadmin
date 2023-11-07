require 'bunny'

module VpsAdmin
  module Supervisor
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

      NodeManager.start(connection)
    end
  end
end
