require 'bunny'

module VpsAdmin
  module Supervisor
    def self.start(cfg)
      connection = Bunny.new(
        hosts: cfg.fetch('hosts'),
        vhost: cfg.fetch('vhost', '/'),
        username: cfg.fetch('username'),
        password: cfg.fetch('password'),
      )
      connection.start

      [
        NodeRpc,
        NodeStatus,
        PoolStatus,
      ].each do |klass|
        instance = klass.new(connection.create_channel)
        instance.start
      end
    end
  end
end
