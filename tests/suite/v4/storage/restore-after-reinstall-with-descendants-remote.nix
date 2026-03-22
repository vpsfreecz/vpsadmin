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
    name = "storage-restore-after-reinstall-with-descendants-remote";

    description = ''
      Restore a VPS root dataset from remote backup after reinstall while
      preserving descendant datasets created on the primary after reinstall.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'restore after reinstall with descendants from remote backup', order: :defined do
        it 'restores the root dataset while preserving current descendants on the primary node' do
          setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-restore-descendants',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'etc/restore-marker',
            content: "root-s1\n"
          )
          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'restore-descendants-s1'
          )

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'etc/restore-marker',
            content: "root-s2\n"
          )
          snap2 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'restore-descendants-s2'
          )

          reinstall = reinstall_vps(
            services,
            admin_user_id: admin_user_id,
            vps_id: setup.fetch('vps_id')
          )
          services.wait_for_chain_state(reinstall.fetch('chain_id'), state: :done)

          wait_until_block_succeeds(name: 'local snapshots removed after reinstall for descendant restore') do
            snapshot_rows_for_dip(services, setup.fetch('src_dip_id')).empty?
          end
          wait_for_vps_running(services, setup.fetch('vps_id'))

          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: setup.fetch('dataset_id'),
            name: 'var',
            pool_fs: primary_pool_fs
          )
          middle = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: child.fetch('dataset_id'),
            name: 'lib',
            pool_fs: primary_pool_fs
          )
          grandchild = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: middle.fetch('dataset_id'),
            name: 'mysql',
            pool_fs: primary_pool_fs
          )

          write_dataset_text(
            node1,
            dataset_path: child.fetch('dataset_path'),
            relative_path: 'keep.txt',
            content: "child-survives\n"
          )
          grandchild_checksum = write_dataset_payload(
            node1,
            dataset_path: grandchild.fetch('dataset_path'),
            relative_path: 'data.bin',
            mib: 4
          )

          restore = rollback_dataset_to_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            snapshot_id: snap2.fetch('id')
          )
          services.wait_for_chain_state(restore.fetch('chain_id'), state: :done)
          wait_for_vps_running(services, setup.fetch('vps_id'))

          expect(
            read_dataset_text(
              node1,
              dataset_path: setup.fetch('primary_dataset_path'),
              relative_path: 'etc/restore-marker'
            )
          ).to eq("root-s2\n")
          expect(
            read_dataset_text(
              node1,
              dataset_path: child.fetch('dataset_path'),
              relative_path: 'keep.txt'
            )
          ).to eq("child-survives\n")
          expect(
            file_checksum(
              node1,
              dataset_path: grandchild.fetch('dataset_path'),
              relative_path: 'data.bin'
            )
          ).to eq(grandchild_checksum)
          expect(node1.zfs_get(fs: child.fetch('dataset_path'), property: 'mounted', timeout: 30).last).to eq('yes')
          expect(node1.zfs_get(fs: grandchild.fetch('dataset_path'), property: 'mounted', timeout: 30).last).to eq('yes')

          snap3 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'restore-descendants-s3'
          )

          expect(
            snapshot_rows_for_dip(services, setup.fetch('dst_dip_id')).map { |row| row.fetch('name') }
          ).to include(snap3.fetch('name'))
        end
      end
    '';
  }
)
