import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
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

    machines = import ../../../machines/v4/cluster/1-node.nix args;

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
          expect(mail_log_count(services, 'expiration_vps_active')).to be >= 1

          daily_response = run_api_task(
            services,
            klass: 'VpsAdmin::API::Tasks::Mail',
            method: :daily_report,
            env: { VPSADMIN_LANG: 'en' }
          )
          expect(daily_response.fetch('chain_ids')).not_to be_empty
          expect(mail_log_count(services, 'daily_report')).to be >= 1
        end
      end
    '';
  }
)
