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
    name = "storage-rollback-with-descendants";

    description = ''
      Roll back a VPS root dataset with descendant datasets present, verify the
      root dataset reverts while descendants are preserved, and confirm later
      backups still work.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'rollback with descendants', order: :defined do
        it 'preserves descendant datasets across rollback and keeps future backups working' do
          setup = create_remote_backup_vps(
            services,
            primary_node: node1,
            backup_node: node2,
            admin_user_id: admin_user_id,
            primary_node_id: node1_id,
            backup_node_id: node2_id,
            hostname: 'storage-rollback-descendants',
            primary_pool_fs: primary_pool_fs,
            backup_pool_fs: backup_pool_fs
          )

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
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'etc/rollback-marker',
            content: "root-v1\n"
          )
          write_dataset_text(
            node1,
            dataset_path: child.fetch('dataset_path'),
            relative_path: 'keep.txt',
            content: "child-v1\n"
          )
          grandchild_checksum_v1 = write_dataset_payload(
            node1,
            dataset_path: grandchild.fetch('dataset_path'),
            relative_path: 'data.bin',
            mib: 4
          )

          snap1 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'descendants-s1'
          )

          write_dataset_text(
            node1,
            dataset_path: setup.fetch('primary_dataset_path'),
            relative_path: 'etc/rollback-marker',
            content: "root-v2\n"
          )
          write_dataset_text(
            node1,
            dataset_path: child.fetch('dataset_path'),
            relative_path: 'keep.txt',
            content: "child-v2\n"
          )
          grandchild_checksum_v2 = write_dataset_payload(
            node1,
            dataset_path: grandchild.fetch('dataset_path'),
            relative_path: 'data.bin',
            mib: 4
          )

          create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'descendants-s2'
          )

          rollback = rollback_dataset_to_snapshot(
            services,
            dataset_id: setup.fetch('dataset_id'),
            snapshot_id: snap1.fetch('id')
          )
          services.wait_for_chain_state(rollback.fetch('chain_id'), state: :done)
          wait_for_vps_running(services, setup.fetch('vps_id'))

          expect(
            read_dataset_text(
              node1,
              dataset_path: setup.fetch('primary_dataset_path'),
              relative_path: 'etc/rollback-marker'
            )
          ).to eq("root-v1\n")
          expect(
            read_dataset_text(
              node1,
              dataset_path: child.fetch('dataset_path'),
              relative_path: 'keep.txt'
            )
          ).to eq("child-v2\n")
          expect(
            file_checksum(
              node1,
              dataset_path: grandchild.fetch('dataset_path'),
              relative_path: 'data.bin'
            )
          ).to eq(grandchild_checksum_v2)
          expect(grandchild_checksum_v2).not_to eq(grandchild_checksum_v1)
          expect(node1.zfs_get(fs: child.fetch('dataset_path'), property: 'mounted', timeout: 30).last).to eq('yes')
          expect(node1.zfs_get(fs: grandchild.fetch('dataset_path'), property: 'mounted', timeout: 30).last).to eq('yes')

          snap3 = create_and_backup_snapshot(
            services,
            admin_user_id: admin_user_id,
            dataset_id: setup.fetch('dataset_id'),
            src_dip_id: setup.fetch('src_dip_id'),
            dst_dip_id: setup.fetch('dst_dip_id'),
            label: 'descendants-s3'
          )

          expect(
            snapshot_rows_for_dip(services, setup.fetch('dst_dip_id')).map { |row| row.fetch('name') }
          ).to include(snap3.fetch('name'))
        end
      end
    '';
  }
)
