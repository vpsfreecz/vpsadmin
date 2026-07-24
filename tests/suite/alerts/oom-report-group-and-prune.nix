import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    creds = import ../../configs/nixos/vpsadmin-credentials.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
    };
  in
  {
    name = "alerts-oom-report-group-and-prune";

    description = ''
      Ingest OOM reports through the supervisor, group their event deliveries,
      send one notification, and prune old reports.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "alerts"
    ];

    machines = import ../../machines/cluster/1-node.nix args;

    testScript = common + ''
      require 'securerandom'

      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        setup_alerts_cluster(services, node)
        services.wait_for_service('vpsadmin-rabbitmq-setup.service')
        services.wait_for_service('vpsadmin-supervisor.service')
        services.wait_for_service('vpsadmin-notification-dispatcher-email.service')
      end

      def publish_oom_reports(services, payloads)
        json = JSON.dump(payloads)

        services.api_ruby_json(code: <<~RUBY)
          require 'bunny'

          conn = Bunny.new(
            hostname: '127.0.0.1',
            vhost: ${builtins.toJSON creds.rabbitmq.vhost},
            username: ${builtins.toJSON creds.rabbitmq.users.supervisor.user},
            password: ${builtins.toJSON creds.rabbitmq.users.supervisor.password}
          )
          conn.start
          channel = conn.create_channel
          exchange = channel.direct(${builtins.toJSON "node:${nodeSeed.domain}"})
          JSON.parse(#{json.inspect}).each do |payload|
            exchange.publish(
              JSON.dump(payload),
              routing_key: 'oom_reports',
              content_type: 'application/json'
            )
          end
          conn.close

          puts JSON.dump(ok: true)
        RUBY
      end

      def oom_payload(vps_id:, cgroup:, count:)
        {
          vps_id: vps_id,
          cgroup: cgroup,
          count: count,
          time: Time.now.to_i,
          invoked_by_pid: 100,
          invoked_by_name: 'ruby',
          killed_pid: 200,
          killed_name: 'worker',
          usage: {
            memory: {
              usage: 512 * 1024 * 1024,
              limit: 1024 * 1024 * 1024,
              failcnt: count
            }
          },
          stats: {
            cache: 64 * 1024 * 1024,
            rss: 448 * 1024 * 1024
          },
          tasks: [
            {
              pid: 200,
              vps_pid: 20,
              name: 'worker',
              uid: 100_000,
              vps_uid: 0,
              tgid: 200,
              total_vm: 131_072,
              rss: 65_536,
              rss_anon: 61_440,
              rss_file: 4096,
              rss_shmem: 0,
              pgtables_bytes: 4096,
              swapents: 0,
              oom_score_adj: 0
            }
          ]
        }
      end

      def grouped_oom_state(services, vps_id:, cgroup_prefix:)
        services.api_ruby_json(code: <<~RUBY)
          route = EventRoute.default_oom_route_for(User.find(#{adminUser.id}))
          reports = OomReport
                    .where(vps_id: #{Integer(vps_id)})
                    .where('cgroup LIKE ?', #{(cgroup_prefix + '%').inspect})
                    .order(:id)
          events = Event
                   .where(
                     event_type: 'vps.oom_report',
                     source_class: 'OomReport',
                     source_id: reports.select(:id)
                   )
                   .order(:id)
          deliveries = EventDelivery
                       .where(event_route: route, event_id: events.select(:id))
                       .order(:id)

          puts JSON.dump(
            report_ids: reports.pluck(:id),
            event_ids: events.pluck(:id),
            events_per_report: events.group(:source_id).count,
            deliveries: deliveries.map do |delivery|
              {
                id: delivery.id,
                event_id: delivery.event_id,
                state: delivery.state,
                event_delivery_group_id: delivery.event_delivery_group_id,
                effective_event_delivery_id: delivery.effective_event_delivery_id,
                group_event_ids: delivery.effective_delivery.group_event_ids
              }
            end
          )
        RUBY
      end

      describe 'OOM event grouping and pruning', order: :defined do
        it 'persists one event per report and sends one grouped notification' do
          vps = create_alert_vps(services, hostname: 'alerts-oom', start: false)
          @oom_vps_id = vps.fetch('id')
          cgroup_prefix = "/integration/grouped/#{SecureRandom.hex(4)}"

          services.api_ruby_json(code: <<~RUBY)
            route = EventRoute.default_oom_route_for(User.find(#{adminUser.id}))
            route.update!(
              group_wait_seconds: 5,
              group_interval_seconds: 60
            )
            puts JSON.dump(id: route.id)
          RUBY

          services.clear_mailpit
          publish_oom_reports(
            services,
            [
              oom_payload(
                vps_id: vps.fetch('id'),
                cgroup: "#{cgroup_prefix}/first",
                count: 1
              ),
              oom_payload(
                vps_id: vps.fetch('id'),
                cgroup: "#{cgroup_prefix}/second",
                count: 2
              )
            ]
          )

          expect_delivered_mail(
            services,
            to: ${builtins.toJSON adminUser.email},
            subject: '[vpsAdmin] VPS alerts-oom had out-of-memory events',
            text_includes: [
              'vpsAdmin recorded out-of-memory events',
              'Selected events: 3 of 3'
            ]
          )

          state = nil
          wait_until_block_succeeds(
            name: 'grouped OOM event deliveries recorded',
            timeout: 120
          ) do
            state = grouped_oom_state(
              services,
              vps_id: vps.fetch('id'),
              cgroup_prefix: cgroup_prefix
            )
            expect(state.fetch('report_ids').length).to eq(2)
            expect(state.fetch('event_ids').length).to eq(2)
            expect(state.fetch('events_per_report').values).to contain_exactly(1, 1)
            expect(state.fetch('deliveries').length).to eq(2)
            expect(state.fetch('deliveries').map { |row| row.fetch('state') })
              .to contain_exactly('sent', 'grouped')
            true
          end

          deliveries = state.fetch('deliveries')
          group_ids = deliveries.map { |row| row.fetch('event_delivery_group_id') }.uniq
          expect(group_ids.length).to eq(1)
          expect(group_ids.first).not_to be_nil

          leader = deliveries.detect { |row| row.fetch('state') == 'sent' }
          follower = deliveries.detect { |row| row.fetch('state') == 'grouped' }
          expect(follower.fetch('effective_event_delivery_id')).to eq(leader.fetch('id'))
          expect(leader.fetch('group_event_ids')).to contain_exactly(
            *state.fetch('event_ids')
          )
        end

        it 'prunes old reports' do
          old = seed_oom_reports(
            services,
            vps_id: @oom_vps_id,
            count: 2,
            created_at: '2.days.ago'
          )
          expect(old_oom_report_count(services)).to be >= 2

          run_api_task(
            services,
            klass: 'VpsAdmin::API::Tasks::OomReport',
            method: :prune,
            env: { DAYS: 1 }
          )

          expect(oom_report_rows(services, old.fetch('ids'))).to eq([])
        end
      end
    '';
  }
)
