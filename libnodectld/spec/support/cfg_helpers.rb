# frozen_string_literal: true

module NodeCtldSpec
  class FakeCfg
    def initialize(data)
      @data = data
    end

    def get(*keys)
      keys.reduce(@data) do |memo, key|
        memo.fetch(key) { memo.fetch(key.to_s) }
      end
    end

    def minimal?
      false
    end
  end

  module CfgHelpers
    class << self
      def install!(node_id:, public_key_path:)
        cfg = ActiveRecord::Base.connection_db_config.configuration_hash
        db_name = cfg[:database] || cfg['database']

        $CFG = FakeCfg.new(
          db: {
            name: db_name,
            host: cfg[:host] || cfg['host'] || '127.0.0.1',
            hosts: [],
            user: cfg[:username] || cfg['username'] || cfg[:user] || cfg['user'],
            pass: cfg[:password] || cfg['password'] || cfg[:pass] || cfg['pass'],
            connect_timeout: 1,
            read_timeout: 1,
            write_timeout: 1,
            retry_interval: 0
          },
          vpsadmin: {
            node_id: node_id,
            transaction_public_key: public_key_path,
            check_interval: 10,
            threads: 4,
            urgent_threads: 2,
            type: :node
          }
        )
      end
    end
  end
end
