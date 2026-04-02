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
    name = "vps-migrate-with-data-check";

    description = ''
      Migrate a VPS to another node, verify the core data survives unchanged,
      and ensure source-side storage is removed after a successful migration.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'VPS migration with data verification', order: :defined do
        it 'moves the VPS to node2 and preserves its root dataset contents' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-migrate-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-dst'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-migrate-dst',
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
            hostname: 'vps-migrate-data'
          )

          info = nil
          wait_until_block_succeeds(name: "dataset info available for VPS #{vps.fetch('id')}") do
            info = dataset_info(services, vps.fetch('id'))
            !info.nil?
          end

          _, vps_row = services.vpsadminctl.succeeds(args: ['vps', 'show', vps.fetch('id').to_s])
          unless vps_row.fetch('vps').fetch('is_running')
            services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          end
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

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

          response = vps_migrate(
            services,
            vps_id: vps.fetch('id'),
            node_id: node2_id,
            send_mail: false
          )
          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          handles = chain_transactions(services, response.fetch('chain_id')).map do |row|
            row.fetch('handle')
          end

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), failure_details.inspect
          expect(handles).to include(
            tx_types(services).fetch('authorize_send_key'),
            tx_types(services).fetch('vps_send_config'),
            tx_types(services).fetch('vps_send_rootfs'),
            tx_types(services).fetch('vps_send_state'),
            tx_types(services).fetch('vps_send_cleanup')
          )

          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node2_id, running: true)
          dst_dataset_path = find_dataset_path_on_node(node2, info.fetch('dataset_full_name'))
          expect(read_dataset_text(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'root/spec-migrate.txt'
          )).to include('vps migration sentinel')
          expect(file_checksum(
            node2,
            dataset_path: dst_dataset_path,
            relative_path: 'root/blob.bin'
          )).to eq(checksum)

          wait_until_block_succeeds(name: 'source VPS dataset removed after migration') do
            expect(node1.zfs_exists?(src_dataset_path, type: 'filesystem', timeout: 30)).to be(false)
            true
          end
        end
      end
    '';
  }
)
