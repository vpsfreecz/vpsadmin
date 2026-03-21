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
    name = "storage-history-divergence-new-tree";

    description = ''
      Create remote backup history, reinstall the VPS to reset primary snapshot
      history, take a new snapshot, and verify the next backup creates a new
      head tree instead of silently warning and returning.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'history divergence after reinstall', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-history-divergence',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'creates a new backup tree instead of silently warning and returning' do
          @snap1 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'divergence-s1'
          )
          @snap2 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'divergence-s2'
          )

          reinstall = reinstall_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: @setup.fetch('vps_id')
          )
          services.wait_for_chain_state(reinstall.fetch('chain_id'), state: :done)

          wait_until_block_succeeds(name: 'local snapshots removed after reinstall') do
            snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).empty?
          end

          @snap3 = create_snapshot(
            services,
            dataset_id: @setup.fetch('dataset_id'),
            dip_id: @setup.fetch('src_dip_id'),
            label: 'divergence-s3'
          )

          response = fire_backup(
            services,
            admin_user_id: admin_user_id,
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id')
          )
          services.wait_for_tree_count(@setup.fetch('dst_dip_id'), count: 2)

          transactions = chain_transactions(services, response.fetch('chain_id'))
          handles = transactions.map { |row| row.fetch('handle') }
          report = backup_topology_report(
            services,
            backup_node: node2,
            dst_dip_id: @setup.fetch('dst_dip_id'),
            backup_dataset_path: @setup.fetch('backup_dataset_path')
          )
          old_tree_entries = report.fetch('db').fetch('entries').select { |row| row.fetch('tree_index') == 0 }
          new_tree_entries = report.fetch('db').fetch('entries').select { |row| row.fetch('tree_index') == 1 }

          expect(response.fetch('chain_id')).not_to be_nil
          expect(report.fetch('db').fetch('trees').count).to eq(2)
          expect(handles).to include(
            @tx_types.fetch('send'),
            @tx_types.fetch('recv'),
            @tx_types.fetch('recv_check')
          )
          expect(handles).not_to include(@tx_types.fetch('local_send'))
          expect(report.fetch('db').fetch('branches').map { |row| row.fetch('tree_index') }.uniq.sort).to eq([0, 1])
          expect(head_tree_row(services, @setup.fetch('dst_dip_id')).fetch('tree_index')).to eq(1)
          expect(old_tree_entries.map { |row| row.fetch('snapshot_name') }.uniq.sort).to eq([
            @snap1.fetch('name'),
            @snap2.fetch('name')
          ])
          expect(new_tree_entries.map { |row| row.fetch('snapshot_name') }.uniq).to eq([@snap3.fetch('name')])
        end
      end
    '';
  }
)
