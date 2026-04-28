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
    name = "tasks-prometheus-export";

    description = ''
      Generate the Prometheus base export through a fresh rake process and
      verify representative metrics are written to the configured file.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "tasks"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        setup_tasks_cluster(services, node, pool_label: 'tasks-prometheus')
      end

      describe 'Prometheus export task', order: :defined do
        it 'writes representative base metrics to EXPORT_FILE' do
          create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'tasks-prometheus',
            start: false
          )
          export_file = '/tmp/vpsadmin-base.prom'

          run_api_rake_task(
            services,
            task: 'vpsadmin:prometheus:export:base',
            env: { EXPORT_FILE: export_file },
            timeout: 300
          )

          services.succeeds("test -s #{Shellwords.escape(export_file)}")
          _, text = services.succeeds("cat #{Shellwords.escape(export_file)}")
          expect(text).to include('vpsadmin_user_count')
          expect(text).to include('vpsadmin_vps_count')
          expect(text).to include('vpsadmin_transaction_chain_count')
        end
      end
    '';
  }
)
