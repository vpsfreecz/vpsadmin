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
    name = "storage-backup-full-incremental-remote";

    description = ''
      Create a 2-node primary+backup setup, run an initial remote backup plus
      two incremental backups, and verify the remote path uses send/recv while
      source rotation preserves the latest shared snapshot needed for the next
      incremental transfer.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote full and incremental backup', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-remote-backup',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

          set_snapshot_retention(
            services,
            dip_id: @setup.fetch('src_dip_id'),
            min_snapshots: 1,
            max_snapshots: 1,
            snapshot_max_age: 0
          )
        end

        it 'backs up the first snapshot over the remote send/recv path' do
          @snap1 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'remote-full-1'
          )

          services.wait_for_tree_count(@setup.fetch('dst_dip_id'), count: 1)
          services.wait_for_branch_count(@setup.fetch('dst_dip_id'), count: 1)

          @head_branch = head_branch_row(services, @setup.fetch('dst_dip_id'))

          transactions = chain_transactions(services, @snap1.fetch('chain_id'))
          handles = transactions.map { |row| row.fetch('handle') }

          expect(handles).to include(
            tx_types(services).fetch('send'),
            tx_types(services).fetch('recv'),
            tx_types(services).fetch('recv_check')
          )
          expect(handles).not_to include(tx_types(services).fetch('local_send'))
          expect(
            transactions.select { |row| row.fetch('handle') == tx_types(services).fetch('send') }.map { |row| row.fetch('node_id') }.uniq
          ).to eq([node1_id])
          expect(
            transactions.select { |row| [tx_types(services).fetch('recv'), tx_types(services).fetch('recv_check')].include?(row.fetch('handle')) }
                        .map { |row| row.fetch('node_id') }
                        .uniq
          ).to eq([node2_id])
          expect(chain_port_reservations(services, @snap1.fetch('chain_id'))).to be_empty
          expect(
            node2.zfs_exists?(
              "#{branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), @head_branch)}@#{@snap1.fetch('name')}",
              type: 'snapshot',
              timeout: 30
            )
          ).to be(true)
        end

        it 'keeps only the latest shared source snapshot after the second backup rotation' do
          @snap2 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'remote-full-2'
          )

          head_branch = head_branch_row(services, @setup.fetch('dst_dip_id'))
          source_snapshots = snapshot_rows_for_dip(services, @setup.fetch('src_dip_id')).map { |row| row.fetch('name') }

          expect(services.mysql_scalar(sql: "SELECT COUNT(*) FROM dataset_trees WHERE dataset_in_pool_id = #{@setup.fetch('dst_dip_id')}")).to eq('1')
          expect(head_branch.fetch('branch_id')).to eq(@head_branch.fetch('branch_id'))
          expect(source_snapshots).not_to include(@snap1.fetch('name'))
          expect(source_snapshots).to include(@snap2.fetch('name'))
          expect(
            node2.zfs_exists?(
              "#{branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), head_branch)}@#{@snap2.fetch('name')}",
              type: 'snapshot',
              timeout: 30
            )
          ).to be(true)
        end

        it 'continues incremental backups on the same remote head branch' do
          @snap3 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            label: 'remote-full-3'
          )

          head_branch = head_branch_row(services, @setup.fetch('dst_dip_id'))
          transactions = chain_transactions(services, @snap3.fetch('chain_id'))
          handles = transactions.map { |row| row.fetch('handle') }
          backup_snapshots = snapshot_rows_for_dip(services, @setup.fetch('dst_dip_id')).map { |row| row.fetch('name') }

          expect(services.mysql_scalar(sql: "SELECT COUNT(*) FROM dataset_trees WHERE dataset_in_pool_id = #{@setup.fetch('dst_dip_id')}")).to eq('1')
          expect(head_branch.fetch('branch_id')).to eq(@head_branch.fetch('branch_id'))
          expect(backup_snapshots).to include(@snap2.fetch('name'), @snap3.fetch('name'))
          expect(handles).to include(
            tx_types(services).fetch('send'),
            tx_types(services).fetch('recv'),
            tx_types(services).fetch('recv_check')
          )
          expect(handles).not_to include(tx_types(services).fetch('local_send'))
          expect(chain_port_reservations(services, @snap3.fetch('chain_id'))).to be_empty
          expect(
            node2.zfs_exists?(
              "#{branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), head_branch)}@#{@snap3.fetch('name')}",
              type: 'snapshot',
              timeout: 30
            )
          ).to be(true)
        end
      end
    '';
  }
)
