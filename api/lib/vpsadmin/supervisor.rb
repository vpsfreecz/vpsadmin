require 'bunny'
require 'yaml'

module VpsAdmin
  module Supervisor
    def self.start
      cfg = YAML.safe_load(File.read(File.join(VpsAdmin::API.root, 'config/supervisor.yml')))

      connection = Bunny.new(
        hosts: cfg['hosts'],
        vhost: cfg['vhost'],
        username: cfg['username'],
        password: cfg['password'],
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

      loop do
        sleep(5)
      end
    end
  end
end
