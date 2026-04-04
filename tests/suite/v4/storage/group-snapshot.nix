import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };
  in
  {
    name = "storage-group-snapshot";

    description = ''
      Create a grouped snapshot for multiple datasets on one node and verify
      the snapshots exist both in the database and in ZFS.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        prepare_node_queues(node)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'group snapshot', order: :defined do
        it 'creates one grouped snapshot transaction for multiple datasets' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'group-snapshot-primary',
            filesystem: primary_pool_fs,
            role: 'primary'
          )

          wait_for_pool_online(services, pool.fetch('id'))

          dataset_a = create_top_level_dataset(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool.fetch('id'),
            dataset_name: 'group-snapshot-a'
          )
          dataset_b = create_top_level_dataset(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool.fetch('id'),
            dataset_name: 'group-snapshot-b'
          )

          response = group_snapshot(
            services,
            admin_user_id: admin_user_id,
            dip_ids: [
              dataset_a.fetch('dataset_in_pool_id'),
              dataset_b.fetch('dataset_in_pool_id')
            ]
          )
          handles = chain_transactions(services, response.fetch('chain_id')).map do |row|
            row.fetch('handle')
          end
          snapshots_a = snapshot_rows_for_dip(services, dataset_a.fetch('dataset_in_pool_id'))
          snapshots_b = snapshot_rows_for_dip(services, dataset_b.fetch('dataset_in_pool_id'))
          snap_a = snapshots_a.last
          snap_b = snapshots_b.last
          dataset_a_path = "#{primary_pool_fs}/#{dataset_a.fetch('dataset_full_name')}"
          dataset_b_path = "#{primary_pool_fs}/#{dataset_b.fetch('dataset_full_name')}"

          expect(handles).to eq([tx_types(services).fetch('create_snapshots')])
          expect(snapshots_a.size).to eq(1)
          expect(snapshots_b.size).to eq(1)
          expect(snap_a.fetch('name')).to eq(snap_b.fetch('name'))
          expect(
            node.zfs_exists?("#{dataset_a_path}@#{snap_a.fetch('name')}", type: 'snapshot', timeout: 30)
          ).to be(true)
          expect(
            node.zfs_exists?("#{dataset_b_path}@#{snap_b.fetch('name')}", type: 'snapshot', timeout: 30)
          ).to be(true)
        end
      end
    '';
  }
)
