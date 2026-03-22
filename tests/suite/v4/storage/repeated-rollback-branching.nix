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
    name = "storage-repeated-rollback-branching";

    description = ''
      Build a repeated remote rollback topology and compare backup dependency
      metadata against the real ZFS origin/clone state on the backup node. The
      core example is intentionally pending because the current metadata model
      can lose enough topology information to make delete ordering unsafe.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'repeated rollback branching', order: :defined do
        it 'creates a VPS with primary storage on node1 and backup storage on node2' do
          @setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-repeated-rollback',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )
        end

        it 'keeps DB dependency metadata aligned with ZFS after repeated rollback branching' do
          topology = build_repeated_rollback_topology(
            services,
            admin_user_id: admin_user_id,
            dataset_id: @setup.fetch('dataset_id'),
            src_dip_id: @setup.fetch('src_dip_id'),
            dst_dip_id: @setup.fetch('dst_dip_id'),
            vps_id: @setup.fetch('vps_id'),
            label_prefix: 'repeat-topology'
          )

          branches = branch_rows_for_dip(services, @setup.fetch('dst_dip_id'))
          entries = branch_entries_for_dip(services, @setup.fetch('dst_dip_id'))
          entry_ids = entries.map { |row| row.fetch('entry_id') }
          snapshot_names = entries.map { |row| row.fetch('snapshot_name') }.uniq
          zfs_refcounts = zfs_reference_counts_by_snapshot(node2, @setup.fetch('backup_dataset_path'))
          db_refcounts = db_reference_counts_by_snapshot(entries)

          pending 'multiple rollback branching can lose enough dependency information that delete ordering becomes unsafe'

          branches.each do |branch|
            origin = node2.zfs_get(
              fs: branch_dataset_path(backup_pool_fs, @setup.fetch('dataset_full_name'), branch),
              property: 'origin',
              timeout: 30
            ).last

            next if origin.nil? || origin.empty? || origin == '-'

            expect(snapshot_names).to include(origin.split('@', 2).last)
          end

          entries.each do |entry|
            next if entry.fetch('parent_entry_id').nil?

            expect(entry_ids).to include(entry.fetch('parent_entry_id'))
          end

          expect(db_refcounts).to eq(zfs_refcounts)

          expect(
            services.mysql_scalar(
              sql: "SELECT COUNT(*) FROM dataset_trees WHERE dataset_in_pool_id = #{@setup.fetch('dst_dip_id')} AND head = 1"
            )
          ).to eq('1')

          branches.group_by { |row| row.fetch('tree_id') }.each_value do |tree_branches|
            expect(tree_branches.count { |row| row.fetch('head') == 1 }).to eq(1)
          end

          expect(topology.fetch('snapshots').fetch('s8').fetch('name')).to be_present
        end
      end
    '';
  }
)
