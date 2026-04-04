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
    name = "vps-migrate-with-subdataset-mounts";

    description = ''
      Migrate a VPS with a mounted subdataset, verify the mount row points to
      the destination dataset, and confirm the subdataset data survives.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      describe 'VPS migration with subdataset mounts', order: :defined do
        it 'remaps mounted subdatasets to the destination dataset in pool' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-submount-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-dst'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-submount-dst',
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
            hostname: 'vps-migrate-submount'
          )

          info = nil
          wait_until_block_succeeds(name: "dataset info available for VPS #{vps.fetch('id')}") do
            info = dataset_info(services, vps.fetch('id'))
            !info.nil?
          end

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: info.fetch('dataset_id'),
            name: 'submount-child',
            pool_fs: primary_pool_fs
          )
          # Keep the real subdataset fixture, but lower its recorded diskspace so
          # the migrated tree still fits on the destination pool in this test VM.
          services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}

            dip = DatasetInPool.find(#{Integer(child.fetch('dip_id'))})
            use = ClusterResourceUse.joins(user_cluster_resource: :cluster_resource).find_by!(
              class_name: 'DatasetInPool',
              table_name: 'dataset_in_pools',
              row_id: dip.id,
              cluster_resources: { name: 'diskspace' }
            )
            ClusterResourceUse.where(id: use.id).update_all(value: 128)

            puts JSON.dump(dip_id: dip.id, diskspace: DatasetInPool.find(dip.id).diskspace)
          RUBY

          write_dataset_text(
            node1,
            dataset_path: child.fetch('dataset_path'),
            relative_path: 'payload/sentinel.txt',
            content: "subdataset mount sentinel\n"
          )

          mount = create_vps_mount(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            dataset_id: child.fetch('dataset_id'),
            mountpoint: '/mnt/sub'
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
          handles = chain_transactions(services, response.fetch('chain_id')).map do |tx|
            tx.fetch('handle')
          end
          rows = vps_mount_rows(services, vps.fetch('id'))
          row = rows.detect { |r| r.fetch('id') == mount.fetch('mount_id') }
          dst_child = dataset_in_pool_info_on_node(
            services,
            dataset_id: child.fetch('dataset_id'),
            node_id: node2_id
          )
          dst_child_path = find_dataset_path_on_node(node2, child.fetch('full_name'))
          _, vps_output = services.vpsadminctl.succeeds(args: ['vps', 'show', vps.fetch('id').to_s])
          sentinel_content =
            begin
              read_dataset_text(
                node2,
                dataset_path: dst_child_path,
                relative_path: 'payload/sentinel.txt'
              )
            rescue StandardError => e
              "#{e.class}: #{e.message}"
            end
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles,
            rows: rows,
            row: row,
            dst_child: dst_child,
            dst_child_path: dst_child_path,
            sentinel_content: sentinel_content,
            vps_after: vps_output.fetch('vps')
          }

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), diagnostic.inspect
          expect(row).not_to be_nil, diagnostic.inspect
          expect(dst_child).not_to be_nil, diagnostic.inspect
          expect(row.fetch('dst')).to eq('/mnt/sub'), diagnostic.inspect
          expect(row.fetch('dataset_in_pool_id')).to eq(dst_child.fetch('dataset_in_pool_id')), diagnostic.inspect
          expect(sentinel_content).to include('subdataset mount sentinel'), diagnostic.inspect

          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node2_id, running: true)
        end
      end
    '';
  }
)
