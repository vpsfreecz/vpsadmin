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
    name = "alerts-incident-report-process";

    description = ''
      Process a pending incident report through the API task and verify the
      task-driven chain updates reporting state, sends mail, and stops the VPS.
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

      describe 'incident report task', order: :defined do
        it 'processes an unreported incident and stops the VPS' do
          vps = create_alert_vps(services, hostname: 'alerts-incident', start: true)
          incident = create_incident_report_row(
            services,
            vps_id: vps.fetch('id'),
            action: :stop
          )

          response = run_api_task(
            services,
            klass: 'VpsAdmin::API::Tasks::IncidentReport',
            method: :process
          )
          wait_for_task_chains_done(services, response, label: 'incident process')

          row = incident_report_row(services, incident.fetch('id'))
          expect(row.fetch('reported_at')).not_to be_nil
          wait_for_vps_on_node(
            services,
            vps_id: vps.fetch('id'),
            node_id: node1_id,
            running: false
          )
          expect(mail_log_count(services, 'vps_incident_report')).to be >= 1
        end
      end
    '';
  }
)
