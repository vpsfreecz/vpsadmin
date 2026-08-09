require 'bunny'

module VpsAdmin
  module Supervisor
    module Console; end
    module Node; end

    def self.create_channel(connection)
      channel = connection.create_channel

      channel.on_uncaught_exception do |exception, consumer|
        connection.logger.error(
          "Uncaught exception from consumer #{consumer}:\n" \
          "#{exception.full_message(highlight: false, order: :top)}"
        )
      end

      channel
    end

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
      NodeManager.start(connection)
    end
  end
end
