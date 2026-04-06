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
    name = "vps-clone-remote-consistent-keep-snapshots";

    description = ''
      Pending contract for keeping transfer snapshots during a remote
      consistent clone.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'remote consistent VPS clone with keep_snapshots', order: :defined do
        it 'keeps transfer snapshots on the source as a pending contract' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-clone-consistent-keep-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-clone-consistent-keep'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-clone-consistent-keep-dst',
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
            hostname: 'vps-clone-consistent-keep'
          )

          src_info = nil
          wait_until_block_succeeds(name: "source dataset info for VPS #{vps.fetch('id')}") do
            src_info = dataset_info(services, vps.fetch('id'))
            !src_info.nil?
          end

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          src_dataset_path = find_dataset_path_on_node(node1, src_info.fetch('dataset_full_name'))
          write_dataset_text(
            node1,
            dataset_path: src_dataset_path,
            relative_path: 'root/spec-clone.txt',
            content: "remote consistent keep snapshots sentinel\n"
          )
          source_snapshots_before = zfs_snapshot_names(node1, src_dataset_path)

          response = vps_clone(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            node_id: node2_id,
            stop: true,
            keep_snapshots: true
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

          clone_info = nil
          wait_until_block_succeeds(name: "clone dataset info for VPS #{response.fetch('cloned_vps_id')}") do
            clone_info = dataset_info(services, response.fetch('cloned_vps_id'))
            !clone_info.nil?
          end

          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)
          wait_for_vps_on_node(
            services,
            vps_id: response.fetch('cloned_vps_id'),
            node_id: node2_id,
            running: true
          )
          clone_dataset_path = find_dataset_path_on_node(node2, clone_info.fetch('dataset_full_name'))
          source_snapshots_after = zfs_snapshot_names(node1, src_dataset_path)
          preserved_snapshots = source_snapshots_after - source_snapshots_before
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles,
            clone_info: clone_info,
            source_snapshots_before: source_snapshots_before,
            source_snapshots_after: source_snapshots_after,
            preserved_snapshots: preserved_snapshots
          }

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), diagnostic.inspect
          expect(read_dataset_text(
            node2,
            dataset_path: clone_dataset_path,
            relative_path: 'root/spec-clone.txt'
          )).to include('remote consistent keep snapshots sentinel'), diagnostic.inspect

          pending(
            'keep_snapshots=true still requires source send-state cleanup, and the current node-side ' \
            'cleanup destroys transfer snapshots while closing the send state'
          )

          expect(handles).not_to include(tx_types(services).fetch('vps_send_cleanup')), diagnostic.inspect
          expect(preserved_snapshots).not_to eq([]), diagnostic.inspect
        end
      end
    '';
  }
)
