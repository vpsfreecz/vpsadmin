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
    name = "user-namespace-lifecycle";
    description = ''
      Allocate, use, disuse, and free a user namespace through API and node runtime.
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

      describe 'user namespace lifecycle', order: :defined do
        it 'uses the namespace map on the node and frees it after disuse' do
          created = create_test_user(
            services,
            login: 'user-namespace-life',
            password: 'secret123'
          )
          expect_chain_done(services, created, label: 'create namespace user')
          namespace = first_user_namespace(services, created.fetch('user_id'))

          vps = create_vps(
            services,
            admin_user_id: created.fetch('user_id'),
            node_id: node1_id,
            hostname: 'user-namespace-life',
            start: true
          )
          wait_for_vps_running(services, vps.fetch('id'))

          vps_row = first_user_vps(services, created.fetch('user_id'))
          expect(vps_row.fetch('user_namespace_map_id')).to eq(namespace.fetch('map_id'))
          expect_osctl_user(node, namespace.fetch('map_id'), exists: true)

          hard_delete_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            reason: 'user namespace lifecycle'
          )
          expect_osctl_user(node, namespace.fetch('map_id'), exists: false)

          freed = free_user_namespace(
            services,
            user_namespace_id: namespace.fetch('user_namespace_id')
          )
          expect_chain_done(services, freed, label: 'free user namespace')
          namespace_after = namespace_rows(
            services,
            user_namespace_id: namespace.fetch('user_namespace_id'),
            map_id: namespace.fetch('map_id'),
            block_ids: namespace.fetch('block_ids')
          )

          expect(namespace_after.fetch('user_namespace_count')).to eq(0)
          expect(namespace_after.fetch('map_count')).to eq(0)
          expect(namespace_after.fetch('block_user_namespace_ids')).to all(be_nil)
        end
      end
    '';
  }
)
