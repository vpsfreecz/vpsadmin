import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
    };
  in
  {
    name = "alerts-lifetime-and-daily-report";

    description = ''
      Drive lifetime expiration warning and daily report generation through API
      tasks and verify their mail logs.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "alerts"
    ];

    machines = import ../../machines/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        setup_alerts_cluster(services, node)
      end

      describe 'lifetime and daily report tasks', order: :defined do
        it 'sends expiration warning and daily report mail' do
          vps = create_alert_vps(services, hostname: 'alerts-lifetime', start: false)
          set_vps_expiration(
            services,
            vps_id: vps.fetch('id'),
            expiration_sql: '2.days.ago'
          )

          services.clear_mailpit
          expiration_response = run_api_task(
            services,
            klass: 'VpsAdmin::API::Tasks::Lifetime',
            method: :mail_expiration,
            env: {
              OBJECTS: 'Vps',
              FROM_DAYS: 0,
              EXECUTE: 'yes'
            }
          )
          expect(expiration_response.fetch('chain_ids')).not_to be_empty
          wait_for_task_chains_done(services, expiration_response, label: 'expiration warning')
          expect(mail_log_count(services, 'expiration_vps_active')).to be >= 1
          expect_delivered_mail(
            services,
            to: ${builtins.toJSON adminUser.email},
            subject: '[vpsAdmin] VPS alerts-lifetime is nearing expiration',
            text_includes: [
              "VPS ##{vps.fetch('id')} (alerts-lifetime) is nearing expiration."
            ]
          )

          services.clear_mailpit
          daily_response = run_api_task(
            services,
            klass: 'VpsAdmin::API::Tasks::Mail',
            method: :daily_report,
            env: { VPSADMIN_LANG: 'en' }
          )
          expect(daily_response.fetch('chain_ids')).to be_empty
          expect(daily_response.fetch('event_ids')).not_to be_empty
          expect(mail_log_count(services, 'daily_report')).to be >= 1
          expect_delivered_mail(
            services,
            to: ${builtins.toJSON adminUser.email},
            subject_prefix: '[vpsAdmin] Daily report ',
            text_includes: 'vpsAdmin daily report'
          )
        end
      end
    '';
  }
)
