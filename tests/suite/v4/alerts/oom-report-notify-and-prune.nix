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
    name = "alerts-oom-report-notify-and-prune";

    description = ''
      Seed OOM report rows directly, notify through the API task, and prune old
      reports without generating a real kernel OOM.
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

      describe 'oom report task', order: :defined do
        it 'notifies users and prunes old reports' do
          vps = create_alert_vps(services, hostname: 'alerts-oom', start: false)
          seeded = seed_oom_reports(services, vps_id: vps.fetch('id'), count: 3)

          response = run_api_task(
            services,
            klass: 'VpsAdmin::API::Tasks::OomReport',
            method: :notify,
            env: { COOLDOWN: 1 }
          )
          wait_for_task_chains_done(services, response, label: 'oom notify')

          expect(mail_log_count(services, 'vps_oom_report')).to be >= 1
          rows = oom_report_rows(services, seeded.fetch('ids'))
          reported_at = rows.map { |row| row.fetch('reported_at') }
          expect(reported_at).not_to include(nil)
          expect(reported_at).not_to include("")

          old = seed_oom_reports(
            services,
            vps_id: vps.fetch('id'),
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
