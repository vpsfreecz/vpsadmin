import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-2-node.nix;
    node1Seed = clusterSeed.nodes.node1;
    node2Seed = clusterSeed.nodes.node2;
    common = import ../storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = node1Seed.id;
      node2Id = node2Seed.id;
    };
  in
  {
    name = "vps-migrate-retain-source-pending";

    description = ''
      Pin the current cleanup_data=false behavior for VPS migration as a
      pending contract until source-side cleanup is skipped correctly.
    '';

    tags = [
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'VPS migration with retained source data', order: :defined do
        it 'will eventually keep the source root dataset when cleanup_data is false' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-retain-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-dst'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-retain-dst',
            filesystem: dst_pool_fs,
            role: 'hypervisor'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))
          wait_for_pool_online(services, dst_pool.fetch('id'))
          generate_migration_keys(services)

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-migrate-retain-source'
          )

          info = nil
          wait_until_block_succeeds(name: "dataset info available for VPS #{vps.fetch('id')}") do
            info = dataset_info(services, vps.fetch('id'))
            !info.nil?
          end

          src_dataset_path = find_dataset_path_on_node(node1, info.fetch('dataset_full_name'))

          write_dataset_text(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/spec-migrate.txt',
            content: "vps migration sentinel\n"
          )
          checksum = write_dataset_payload(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/blob.bin',
            mib: 4
          )

          pending('VPS OsToOs migration does not yet honor cleanup_data: false')

          response = vps_migrate(
            services,
            vps_id: vps.fetch('id'),
            node_id: node2_id,
            cleanup_data: false,
            send_mail: false
          )
          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          dst_dataset_path = find_dataset_path_on_node(node2, info.fetch('dataset_full_name'))

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_failure_details(
            services,
            response.fetch('chain_id')
          ).inspect
          expect(read_dataset_text(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'root/spec-migrate.txt'
          )).to include('vps migration sentinel')
          expect(read_dataset_text(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/spec-migrate.txt'
          )).to include('vps migration sentinel')
          expect(file_checksum(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'root/blob.bin'
          )).to eq(checksum)
          expect(file_checksum(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/blob.bin'
          )).to eq(checksum)
        end
      end
    '';
  }
)
