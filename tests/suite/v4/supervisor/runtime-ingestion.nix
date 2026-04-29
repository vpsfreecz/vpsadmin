import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test-1-node.nix;
    creds = import ../../../configs/nixos/vpsadmin-credentials.nix;
    nodeSeed = seed.nodes.node;
    common = import ./common.nix {
      adminUserId = seed.adminUser.id;
      node1Id = nodeSeed.id;
      nodeDomain = nodeSeed.domain;
      rabbitmqVhost = creds.rabbitmq.vhost;
      rabbitSupervisorUser = creds.rabbitmq.users.supervisor;
    };
  in
  {
    name = "supervisor-runtime-ingestion";

    description = ''
      Publish runtime state messages through RabbitMQ and verify that the
      running supervisor persists node, VPS, storage, network, mount, and event
      state.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "supervisor"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        setup_supervisor_cluster(services, node)

        @status_vps = create_supervisor_vps(
          services,
          hostname: 'supervisor-status',
          start: false
        )
        ensure_vps_current_status(services, @status_vps.fetch('id'))

        @storage_vps = create_supervisor_vps(
          services,
          hostname: 'supervisor-storage',
          start: false
        )
        ensure_vps_current_status(services, @storage_vps.fetch('id'))
        @storage_fixture = supervisor_vps_info(services, @storage_vps.fetch('id'))

        @network_vps = create_supervisor_vps(
          services,
          hostname: 'supervisor-network',
          start: false
        )
        @netif = ensure_supervisor_netif(services, vps_id: @network_vps.fetch('id'))

        @events_vps = create_supervisor_vps(
          services,
          hostname: 'supervisor-events',
          start: false
        )
        ensure_vps_current_status(services, @events_vps.fetch('id'))
        @events_fixture = supervisor_vps_info(services, @events_vps.fetch('id'))

        export_network = ensure_private_export_network_with_ips(
          services,
          admin_user_id: admin_user_id,
          dataset_id: @events_fixture.fetch('dataset_id'),
          count: 1
        )
        @export_host_addr = export_network.fetch('ip_addresses').first.fetch('addr')
        @export = seed_supervisor_export(
          services,
          dataset_id: @events_fixture.fetch('dataset_id'),
          ip_address_id: export_network.fetch('ip_addresses').first.fetch('id')
        )
      end

      describe 'supervisor status ingestion' do
        it 'ingests node status' do
          t = Time.utc(2026, 4, 5, 12, 0, 0)

          publish_supervisor_payload(
            services,
            routing_key: 'statuses',
            payload: {
              id: node1_id,
              time: t.to_i,
              uptime: 9876,
              nproc: 55,
              loadavg: { '1' => 0.7, '5' => 0.4, '15' => 0.2 },
              vpsadmin_version: 'integration',
              kernel: '6.8.0',
              cgroup_version: 2,
              cpus: 4,
              cpu: {
                user: 11.0,
                nice: 0.0,
                system: 6.0,
                idle: 80.0,
                iowait: 1.0,
                irq: 1.0,
                softirq: 1.0,
                guest: 0.0
              },
              memory: { total: 8 * 1024 * 1024, used: 3 * 1024 * 1024 },
              swap: { total: 1024 * 1024, used: 128 * 1024 },
              storage: {
                state: 'online',
                scan: 'none',
                scan_percent: nil,
                checked_at: t.to_i
              },
              arc: {
                c_max: 512 * 1024 * 1024,
                c: 256 * 1024 * 1024,
                size: 128 * 1024 * 1024,
                hitpercent: 97.0
              }
            }
          )

          row = wait_for_row('node current status from supervisor') do
            row = node_current_status_row(services, node_id: node1_id)
            row if row && row.fetch('uptime').to_i == 9876
          end

          expect(row.fetch('process_count')).to eq(55)
          expect(row.fetch('total_memory')).to eq(8192)
          expect(row.fetch('used_memory')).to eq(3072)
          expect(row.fetch('total_swap')).to eq(1024)
          expect(row.fetch('used_swap')).to eq(128)
          expect(row.fetch('arc_size')).to eq(128)
          expect(row.fetch('pool_state')).to eq(1)
          expect(row.fetch('pool_scan')).to eq(1)
        end

        it 'ingests VPS status' do
          t = Time.utc(2026, 4, 5, 12, 5, 0)
          vps_id = @status_vps.fetch('id')

          publish_supervisor_payload(
            services,
            routing_key: 'vps_statuses',
            payload: {
              id: vps_id,
              time: t.to_i,
              status: true,
              running: true,
              in_rescue_mode: false,
              uptime: 4321,
              loadavg: { '1' => 0.2, '5' => 0.1, '15' => 0.05 },
              process_count: 24,
              used_memory: 384 * 1024 * 1024,
              cpu_usage: 25.0,
              hostname: 'supervisor-status-updated'
            }
          )

          row = wait_for_row('vps current status from supervisor') do
            row = vps_current_status_row(services, vps_id: vps_id)
            row if row && row.fetch('uptime').to_i == 4321
          end

          expect(row.fetch('status')).to eq(1)
          expect(row.fetch('is_running')).to eq(1)
          expect(row.fetch('process_count')).to eq(24)
          expect(row.fetch('used_memory')).to eq(384)
          expect(row.fetch('cpu_idle')).to eq(75.0)
        end
      end

      describe 'supervisor storage ingestion' do
        it 'ingests storage status batches and updates disk totals' do
          t = Time.utc(2026, 4, 5, 13, 0, 0)
          props = @storage_fixture.fetch('properties')
          refquota = props.fetch('refquota')
          referenced = props.fetch('referenced')

          publish_supervisor_payload(
            services,
            routing_key: 'storage_statuses',
            payload: {
              time: t.to_i,
              message_id: 40,
              properties: [
                {
                  id: refquota.fetch('id'),
                  name: 'refquota',
                  value: 12 * 1024 * 1024 * 1024,
                  vps_id: @storage_vps.fetch('id')
                },
                {
                  id: referenced.fetch('id'),
                  name: 'referenced',
                  value: 5 * 1024 * 1024 * 1024,
                  vps_id: @storage_vps.fetch('id')
                }
              ]
            }
          )

          refquota_row = wait_for_row('refquota property update') do
            row = dataset_property_row(services, property_id: refquota.fetch('id'))
            row if row.fetch('value').to_i == 12_288
          end
          referenced_row = dataset_property_row(
            services,
            property_id: referenced.fetch('id')
          )

          expect(refquota_row.fetch('value')).to eq(12_288)
          expect(referenced_row.fetch('value')).to eq(5120)

          status = wait_for_row('vps disk sums') do
            row = vps_current_status_row(services, vps_id: @storage_vps.fetch('id'))
            row if row && row.fetch('total_diskspace').to_i == 12_288
          end
          expect(status.fetch('used_diskspace')).to eq(5120)

          histories = dataset_property_history_rows(
            services,
            property_id: referenced.fetch('id')
          )
          expect(histories.size).to eq(1)
          expect(histories.first.fetch('value')).to eq(5120)
        end

        it 'ingests dataset expansion events' do
          t = Time.utc(2026, 4, 5, 13, 5, 0)
          dataset_id = @storage_fixture.fetch('dataset_id')
          refquota_id = @storage_fixture.fetch('properties').fetch('refquota').fetch('id')

          publish_supervisor_payload(
            services,
            routing_key: 'dataset_expansions',
            payload: {
              dataset_id: dataset_id,
              original_refquota: 10_240,
              new_refquota: 14_336,
              added_space: 4096,
              time: t.to_i
            }
          )

          histories = nil
          wait_until_block_succeeds(name: 'dataset expansion history') do
            histories = dataset_expansion_history_rows(services, dataset_id: dataset_id)
            expect(histories).not_to be_empty
            true
          end

          expect(histories.last.fetch('original_refquota')).to eq(10_240)
          expect(histories.last.fetch('new_refquota')).to eq(14_336)
          expect(histories.last.fetch('added_space')).to eq(4096)

          refquota = wait_for_row('expanded refquota property') do
            row = dataset_property_row(services, property_id: refquota_id)
            row if row.fetch('value').to_i == 14_336
          end
          expect(refquota.fetch('value')).to eq(14_336)
        end
      end

      describe 'supervisor network ingestion' do
        it 'ingests network monitor snapshots' do
          t = Time.utc(2026, 4, 5, 14, 0, 0)

          publish_supervisor_payload(
            services,
            routing_key: 'net_monitor',
            payload: {
              monitors: [
                {
                  id: @netif.fetch('id'),
                  time: t.to_i,
                  bytes_in: 1000,
                  bytes_out: 2500,
                  packets_in: 100,
                  packets_out: 250,
                  delta: 60,
                  bytes_in_readout: 10_000,
                  bytes_out_readout: 20_000,
                  packets_in_readout: 1000,
                  packets_out_readout: 2000
                }
              ]
            }
          )

          row = wait_for_row('network monitor row') do
            row = net_monitor_row(services, netif_id: @netif.fetch('id'))
            row if row && row.fetch('bytes').to_i == 3500
          end

          expect(row.fetch('bytes_in')).to eq(1000)
          expect(row.fetch('bytes_out')).to eq(2500)
          expect(row.fetch('packets')).to eq(350)
          expect(row.fetch('delta')).to eq(60)
        end

        it 'ingests accounting buckets additively' do
          t = Time.utc(2026, 4, 6, 10, 30, 0)
          payload = lambda do |bytes_in, bytes_out, packets_in, packets_out|
            {
              accounting: [
                {
                  id: @netif.fetch('id'),
                  user_id: @netif.fetch('user_id'),
                  time: t.to_i,
                  bytes_in: bytes_in,
                  bytes_out: bytes_out,
                  packets_in: packets_in,
                  packets_out: packets_out
                }
              ]
            }
          end

          publish_supervisor_payload(
            services,
            routing_key: 'net_accounting',
            payload: payload.call(100, 200, 10, 20)
          )
          publish_supervisor_payload(
            services,
            routing_key: 'net_accounting',
            payload: payload.call(300, 400, 30, 40)
          )

          daily = wait_for_row('daily network accounting') do
            row = accounting_row(
              services,
              table: 'network_interface_daily_accountings',
              netif_id: @netif.fetch('id'),
              user_id: @netif.fetch('user_id'),
              year: t.year,
              month: t.month,
              day: t.day
            )
            row if row && row.fetch('bytes_in').to_i == 400
          end
          monthly = accounting_row(
            services,
            table: 'network_interface_monthly_accountings',
            netif_id: @netif.fetch('id'),
            user_id: @netif.fetch('user_id'),
            year: t.year,
            month: t.month
          )
          yearly = accounting_row(
            services,
            table: 'network_interface_yearly_accountings',
            netif_id: @netif.fetch('id'),
            user_id: @netif.fetch('user_id'),
            year: t.year
          )

          [daily, monthly, yearly].each do |row|
            expect(row.fetch('bytes_in')).to eq(400)
            expect(row.fetch('bytes_out')).to eq(600)
            expect(row.fetch('packets_in')).to eq(40)
            expect(row.fetch('packets_out')).to eq(60)
          end
        end
      end

      describe 'supervisor mount ingestion' do
        it 'creates, updates, and deletes export mounts to match the payload' do
          stale = seed_export_mount(
            services,
            vps_id: @events_vps.fetch('id'),
            export_id: @export.fetch('id'),
            mountpoint: '/mnt/stale',
            nfs_version: '4'
          )

          publish_supervisor_payload(
            services,
            routing_key: 'export_mounts',
            payload: {
              vps_id: @events_vps.fetch('id'),
              time: Time.utc(2026, 4, 5, 15, 0, 0).to_i,
              mounts: [
                {
                  server_address: @export_host_addr,
                  server_path: @export.fetch('path'),
                  mountpoint: '/mnt/export',
                  nfs_version: '4'
                }
              ]
            }
          )

          rows = nil
          wait_until_block_succeeds(name: 'export mount created and stale removed') do
            rows = export_mount_rows(services, vps_id: @events_vps.fetch('id'))
            expect(rows.size).to eq(1)
            expect(rows.first.fetch('mountpoint')).to eq('/mnt/export')
            true
          end
          expect(rows.first.fetch('nfs_version')).to eq('4')
          expect(rows.map { |row| row.fetch('id') }).not_to include(stale.fetch('id'))

          publish_supervisor_payload(
            services,
            routing_key: 'export_mounts',
            payload: {
              vps_id: @events_vps.fetch('id'),
              time: Time.utc(2026, 4, 5, 15, 5, 0).to_i,
              mounts: [
                {
                  server_address: @export_host_addr,
                  server_path: @export.fetch('path'),
                  mountpoint: '/mnt/export',
                  nfs_version: '4.2'
                }
              ]
            }
          )

          row = wait_for_row('export mount updated') do
            rows = export_mount_rows(services, vps_id: @events_vps.fetch('id'))
            rows.first if rows.size == 1 && rows.first.fetch('nfs_version') == '4.2'
          end
          expect(row.fetch('mountpoint')).to eq('/mnt/export')
        end

        it 'updates VPS mount state from mount reports' do
          mount = seed_vps_mount(
            services,
            vps_id: @events_vps.fetch('id'),
            mountpoint: '/mnt/data'
          )

          publish_supervisor_payload(
            services,
            routing_key: 'vps_mounts',
            payload: {
              id: mount.fetch('id'),
              vps_id: @events_vps.fetch('id'),
              state: 'mounted',
              time: Time.utc(2026, 4, 5, 15, 10, 0).to_i
            }
          )

          row = wait_for_row('vps mount state') do
            row = vps_mount_row(services, mount_id: mount.fetch('id'))
            row if row && row.fetch('current_state').to_i == 1
          end
          expect(row.fetch('current_state')).to eq(1)
        end
      end

      describe 'supervisor VPS event ingestion' do
        it 'marks halt events and logs reboot events' do
          vps_id = @events_vps.fetch('id')

          publish_supervisor_payload(
            services,
            routing_key: 'vps_events',
            payload: {
              id: vps_id,
              time: Time.utc(2026, 4, 5, 15, 20, 0).to_i,
              type: 'exit',
              opts: { exit_type: 'halt' }
            }
          )

          wait_until_block_succeeds(name: 'halted current status') do
            row = vps_current_status_row(services, vps_id: vps_id)
            expect(row.fetch('halted')).to eq(1)
            true
          end
          expect(object_history_count(services, object_type: 'Vps', object_id: vps_id, event_type: 'halt')).to eq(1)

          services.api_ruby_json(code: <<~RUBY)
            VpsCurrentStatus.find_by!(vps_id: #{Integer(vps_id)}).update!(halted: false)
            puts JSON.dump(ok: true)
          RUBY

          publish_supervisor_payload(
            services,
            routing_key: 'vps_events',
            payload: {
              id: vps_id,
              time: Time.utc(2026, 4, 5, 15, 25, 0).to_i,
              type: 'exit',
              opts: { exit_type: 'reboot' }
            }
          )

          wait_until_block_succeeds(name: 'reboot history') do
            expect(object_history_count(services, object_type: 'Vps', object_id: vps_id, event_type: 'reboot')).to eq(1)
            expect(vps_current_status_row(services, vps_id: vps_id).fetch('halted')).to eq(0)
            true
          end
        end

        it 'creates incident reports for oomd stop events' do
          vps_id = @events_vps.fetch('id')

          publish_supervisor_payload(
            services,
            routing_key: 'vps_events',
            payload: {
              id: vps_id,
              time: Time.utc(2026, 4, 5, 15, 30, 0).to_i,
              type: 'oomd',
              opts: { action: 'stop' }
            }
          )

          reports = nil
          wait_until_block_succeeds(name: 'oomd incident report') do
            reports = incident_reports_for_vps(services, vps_id: vps_id)
            expect(reports.size).to eq(1)
            true
          end

          expect(reports.first.fetch('codename')).to eq('oomd')
          expect(reports.first.fetch('subject')).to eq('Stop due to abuse')
          expect(reports.first.fetch('text')).to include('was stopped')
        end
      end
    '';
  }
)
