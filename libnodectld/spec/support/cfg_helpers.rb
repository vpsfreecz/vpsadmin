# frozen_string_literal: true

module NodeCtldSpec
  class FakeCfg
    def initialize(data)
      @data = data
      @callbacks = Hash.new { |hash, key| hash[key] = [] }
    end

    def get(*keys)
      keys.reduce(@data) do |memo, key|
        memo.fetch(key) { memo.fetch(key.to_s) }
      end
    end

    def patch(change)
      deep_merge!(@data, change)
      @callbacks.each_value do |callbacks|
        callbacks.each(&:call)
      end
    end

    def on_update(name, &block)
      @callbacks[name] << block
    end

    def reload; end

    def minimal?
      false
    end

    protected

    def deep_merge!(target, change)
      change.each do |key, value|
        if target[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge!(target[key], value)
        else
          target[key] = value
        end
      end

      target
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
            type: :node,
            veth_map_interval: 60,
            queues: {
              general: { threads: 2, urgent: 1, start_delay: 0 },
              storage: { threads: 2, urgent: 1, start_delay: 0 },
              network: { threads: 2, urgent: 1, start_delay: 0 },
              vps: { threads: 2, urgent: 1, start_delay: 0 },
              zfs_send: { threads: 2, urgent: 1, start_delay: 0 },
              zfs_recv: { threads: 2, urgent: 1, start_delay: 0 },
              mail: { threads: 2, urgent: 1, start_delay: 0 },
              dns: { threads: 2, urgent: 1, start_delay: 0 },
              outage: { threads: 2, urgent: 1, start_delay: 0 },
              queue: { threads: 2, urgent: 1, start_delay: 0 },
              rollback: { threads: 2, urgent: 1, start_delay: 0 }
            }
          },
          console: {
            enable: true
          },
          route_check: {
            default_timeout: 30
          },
          traffic_accounting: {
            enable: true,
            update_interval: 60,
            log_interval: 300,
            batch_size: 100
          },
          node: {
            cpu_usage_measure_delay: 60
          },
          dns_server: {
            status_interval: 60,
            statistics_url: 'http://127.0.0.1:8053/',
            bind_workdir: Dir.tmpdir
          }
        )
      end
    end
  end
end
