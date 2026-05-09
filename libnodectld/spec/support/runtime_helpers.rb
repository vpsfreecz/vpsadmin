# frozen_string_literal: true

module NodeCtldSpec
  class BunnySpecExchange
    def marker; end
  end

  class BunnySpecChannel
    def direct(_name); end
  end

  module RuntimeHelpers
    def stub_node_bunny
      exchange = instance_double(NodeCtldSpec::BunnySpecExchange)
      channel = instance_double(NodeCtldSpec::BunnySpecChannel, direct: exchange)

      allow(NodeCtld::NodeBunny).to receive_messages(create_channel: channel, exchange_name: 'node:spec')

      exchange
    end

    def runtime_cfg(overrides = {})
      base = {
        vpsadmin: {
          node_id: 1,
          type: :node,
          veth_map_interval: 60,
          queues: NodeCtld::Queues::QUEUES.to_h do |name|
            [name, { threads: 2, urgent: 1, start_delay: 0 }]
          end
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
          bind_workdir: Dir.tmpdir,
          transfer_log_cursor_file: File.join(Dir.tmpdir, 'dns-transfer-log.cursor'),
          transfer_log_command: 'journalctl',
          transfer_log_identifiers: ['named'],
          transfer_log_unit: nil
        }
      }

      NodeCtldSpec::FakeCfg.new(deep_merge(base, overrides))
    end

    def deep_merge(base, overrides)
      base.merge(overrides) do |_key, old_value, new_value|
        if old_value.is_a?(Hash) && new_value.is_a?(Hash)
          deep_merge(old_value, new_value)
        else
          new_value
        end
      end
    end
  end
end
