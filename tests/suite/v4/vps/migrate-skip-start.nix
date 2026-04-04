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
    name = "vps-migrate-skip-start";

    description = ''
      Migrate a running VPS with skip_start=true, force the destination start
      to fail, and verify the chain still finishes done with the VPS moved.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'VPS migration with skip_start', order: :defined do
        it 'finishes done when the destination start fails and keep-going is set' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-skip-start-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-dst'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-skip-start-dst',
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
            hostname: 'vps-migrate-skip-start'
          )

          info = nil
          wait_until_block_succeeds(name: "dataset info available for VPS #{vps.fetch('id')}") do
            info = dataset_info(services, vps.fetch('id'))
            !info.nil?
          end

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
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

          start_handle = tx_types(services).fetch('vps_start')
          response = vps_migrate_with_hooks(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            node_id: node2_id,
            skip_start: true,
            send_mail: false,
            remove_dst_config_before_start: true
          )
          final_state = wait_for_chain_states_local(
            services,
            response.fetch('chain_id'),
            %i[done failed fatal resolved]
          )
          handles = chain_transactions(services, response.fetch('chain_id')).map do |row|
            row.fetch('handle')
          end
          start_detail = wait_for_chain_failure_detail(
            services,
            response.fetch('chain_id'),
            handle: start_handle,
            timeout: 120
          )
          failure_details = chain_failure_details(services, response.fetch('chain_id'))
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node2_id, running: false)
          _, vps_output = services.vpsadminctl.succeeds(args: ['vps', 'show', vps.fetch('id').to_s])
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            handles: handles,
            start_detail: start_detail,
            failure_details: failure_details,
            vps_after: vps_output.fetch('vps')
          }

          expect(handles).to include(start_handle), diagnostic.inspect
          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), diagnostic.inspect
          expect(start_detail.fetch('handle')).to eq(start_handle)
          expect(start_detail.fetch('status')).to eq(0)
          expect(start_detail.fetch('error').to_s).not_to eq("")
          expect(vps_output.fetch('vps').fetch('node').fetch('id')).to eq(node2_id), diagnostic.inspect
          expect(vps_output.fetch('vps').fetch('is_running')).to eq(false), diagnostic.inspect

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

          wait_until_block_succeeds(name: 'source VPS dataset removed after skip-start migration') do
            expect(node1.zfs_exists?(src_dataset_path, type: 'filesystem', timeout: 30)).to be(false)
            true
          end
        end
      end
    '';
  }
)
