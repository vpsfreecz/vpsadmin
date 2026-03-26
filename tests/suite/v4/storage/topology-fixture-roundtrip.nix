import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-2-node.nix;
    node1Seed = clusterSeed.nodes.node1;
    node2Seed = clusterSeed.nodes.node2;
    common = import ./remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = node1Seed.id;
      node2Id = node2Seed.id;
    };
  in
  {
    name = "storage-topology-fixture-roundtrip";

    description = ''
      Build a complex remote backup topology, dump it as normalized JSON, and
      prove the delete-order diagnostic is stable when replayed from the saved
      fixture.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'topology fixture roundtrip', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-topology-fixture',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'captures and replays a normalized topology fixture' do
          build_complex_multi_tree_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            vps_id: @setup.fetch('vps_id'),
            label_prefix: 'fixture-roundtrip'
          )

          fixture_path = '/tmp/storage-topology-roundtrip.json'
          payload = capture_backup_topology_fixture(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path'),
            path: fixture_path,
            metadata: {
              'suite' => 'storage-topology-fixture-roundtrip',
              'dataset_id' => @setup.fetch('dataset_id')
            }
          )
          loaded = load_topology_fixture(fixture_path)
          live_contract = delete_order_leaf_contract(payload.fetch('report'))
          fixture_contract = delete_order_leaf_contract_from_fixture(fixture_path)

          expect(File.exist?(fixture_path)).to be(true)
          expect(loaded.fetch('version')).to eq(1)
          expect(loaded.fetch('metadata')).to include(
            'suite' => 'storage-topology-fixture-roundtrip',
            'dataset_id' => @setup.fetch('dataset_id')
          )
          expect(normalize_backup_topology_report(loaded.fetch('report'))).to eq(loaded.fetch('report'))
          expect(loaded.fetch('report')).to eq(payload.fetch('report'))
          expect(loaded.fetch('diagnostic')).to eq(payload.fetch('diagnostic'))
          expect(loaded.fetch('diagnostic')).to eq(delete_order_diagnostic(loaded.fetch('report')))
          expect(fixture_contract).to eq(live_contract)
        end
      end
    '';
  }
)
