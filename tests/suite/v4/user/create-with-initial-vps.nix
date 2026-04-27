import ../../../make-test.nix (
  { ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeId = clusterSeed.node.id;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeId;
    };
  in
  {
    name = "user-create-with-initial-vps";
    description = ''
      Create users through User::Create with the optional initial VPS path.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "user"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        setup_user_lifecycle_cluster(services, node)
      end

      describe 'user create with initial VPS', order: :defined do
        it 'creates an active user with a running initial VPS' do
          created = create_test_user(
            services,
            login: 'user-create-active',
            password: 'secret123',
            create_vps: true,
            activate: true,
            node_id: node1_id,
            os_template_id: 1
          )
          audit, = expect_chain_done(services, created, label: 'active user create')

          row = user_row(services, created.fetch('user_id'))
          vps = first_user_vps(services, created.fetch('user_id'))
          wait_for_vps_running(services, vps.fetch('id'))

          expect(row.fetch('object_state')).to eq('active'), audit.inspect
          expect(row.fetch('environment_user_config_count')).to be > 0
          expect(row.fetch('user_cluster_resource_count')).to be > 0
          expect(row.fetch('personal_package_count')).to be > 0
          expect(vps.fetch('object_state')).to eq('active')
          expect(vps.fetch('is_running')).to eq(true)
        end

        it 'creates a suspended user with a stopped initial VPS' do
          created = create_test_user(
            services,
            login: 'user-create-suspended',
            password: 'secret123',
            create_vps: true,
            activate: false,
            node_id: node1_id,
            os_template_id: 1
          )
          audit, = expect_chain_done(services, created, label: 'suspended user create')

          row = user_row(services, created.fetch('user_id'))
          vps = first_user_vps(services, created.fetch('user_id'))

          expect(row.fetch('object_state')).to eq('suspended'), audit.inspect
          expect(vps.fetch('object_state')).to eq('active')
          expect(vps.fetch('is_running')).not_to eq(true)
        end
      end
    '';
  }
)
