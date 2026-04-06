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
      manageCluster = false;
    };
  in
  {
    name = "vps-replace-with-descendants-and-mounts";

    description = ''
      Replace a VPS with descendant datasets and mounts, remap the descendant
      mount onto the replacement, and keep external mounts out of the
      replacement.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      before(:suite) do
        [services, node1, node2].each(&:start)
        services.wait_for_vpsadmin_api
        [node1, node2].each do |machine|
          wait_for_running_nodectld(machine)
          prepare_node_queues(machine)
        end
        [node1_id, node2_id].each do |node_id|
          wait_for_node_ready(services, node_id)
        end
        services.unlock_transaction_signing_key(passphrase: 'test')
        set_user_mailer_enabled(
          services,
          admin_user_id: admin_user_id,
          user_id: admin_user_id,
          enabled: false
        )
      end

      describe 'remote VPS replace with descendants and mounts', order: :defined do
        it 'copies descendant datasets, remaps descendant mounts, and skips external mounts' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-replace-desc-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          dst_pool_fs = 'tank/ct-replace-desc'
          dst_pool = create_pool(
            services,
            node_id: node2_id,
            label: 'vps-replace-desc-dst',
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
            hostname: 'vps-replace-desc'
          )

          src_info = nil
          wait_until_block_succeeds(name: "source dataset info for VPS #{vps.fetch('id')}") do
            src_info = dataset_info(services, vps.fetch('id'))
            !src_info.nil?
          end

          child = create_descendant_dataset(
            services,
            admin_user_id: admin_user_id,
            parent_dataset_id: src_info.fetch('dataset_id'),
            name: 'replace-desc-child',
            pool_fs: primary_pool_fs
          )
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

            puts JSON.dump(dip_id: dip.id)
          RUBY

          descendant_mount = create_vps_mount(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            dataset_id: child.fetch('dataset_id'),
            mountpoint: '/mnt/replace-desc'
          )

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)
          attach_test_vps_ip(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            addr: '198.51.100.40'
          )

          src_root_path = find_dataset_path_on_node(node1, src_info.fetch('dataset_full_name'))
          write_dataset_text(
            node1,
            dataset_path: src_root_path,
            relative_path: 'root/root.txt',
            content: "replace descendant root sentinel\n"
          )
          write_dataset_text(
            node1,
            dataset_path: child.fetch('dataset_path'),
            relative_path: 'payload/child.txt',
            content: "replace descendant child sentinel\n"
          )

          services.vpsadminctl.succeeds(
            args: ['vps', 'stop', vps.fetch('id').to_s],
            parameters: { force: true }
          )
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: false)

          external = create_top_level_dataset(
            services,
            admin_user_id: admin_user_id,
            pool_id: src_pool.fetch('id'),
            dataset_name: 'replace-external'
          )
          services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}

            dip = DatasetInPool.find(#{Integer(external.fetch('dataset_in_pool_id'))})
            use = ClusterResourceUse.joins(user_cluster_resource: :cluster_resource).find_by!(
              class_name: 'DatasetInPool',
              table_name: 'dataset_in_pools',
              row_id: dip.id,
              cluster_resources: { name: 'diskspace' }
            )
            ClusterResourceUse.where(id: use.id).update_all(value: 128)

            puts JSON.dump(dip_id: dip.id)
          RUBY

          # Seed a legacy external mount row directly; the supported mount API
          # only accepts VPS subdatasets.
          external_mount = services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}

            vps = Vps.find(#{Integer(vps.fetch('id'))})
            dip = DatasetInPool.find(#{Integer(external.fetch('dataset_in_pool_id'))})
            mount = Mount.create!(
              vps: vps,
              dataset_in_pool: dip,
              dst: '/mnt/external',
              mount_opts: '--bind',
              umount_opts: '-f',
              mount_type: 'bind',
              mode: 'rw',
              user_editable: false,
              confirmed: Mount.confirmed(:confirmed),
              enabled: true,
              master_enabled: true
            )

            puts JSON.dump(
              mount_id: mount.id,
              dataset_in_pool_id: mount.dataset_in_pool_id
            )
          RUBY

          response = vps_replace(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            node_id: node2_id,
            start: true,
            reason: 'replace descendants integration'
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
          chain_diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles
          }

          expect(final_state).to eq(services.class::CHAIN_STATES[:done]), chain_diagnostic.inspect

          replacement_info = nil
          wait_until_block_succeeds(name: "replacement dataset info for VPS #{response.fetch('replaced_vps_id')}") do
            replacement_info = dataset_info(services, response.fetch('replaced_vps_id'))
            !replacement_info.nil?
          end

          wait_for_vps_on_node(
            services,
            vps_id: response.fetch('replaced_vps_id'),
            node_id: node2_id,
            running: true
          )
          replacement_dataset_rows = vps_dataset_rows(services, response.fetch('replaced_vps_id'))
          replacement_mount_rows = vps_mount_rows(services, response.fetch('replaced_vps_id'))
          replacement_child_row = replacement_dataset_rows.detect do |row|
            row.fetch('full_name').end_with?('/replace-desc-child')
          end
          replacement_descendant_mount = replacement_mount_rows.detect do |row|
            row.fetch('dst') == '/mnt/replace-desc'
          end
          replacement_external_mount = replacement_mount_rows.detect do |row|
            row.fetch('dst') == '/mnt/external'
          end
          old_row = vps_unscoped_row(services, vps.fetch('id'))
          replacement_root_path = find_dataset_path_on_node(
            node2,
            replacement_info.fetch('dataset_full_name')
          )
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles,
            old_row: old_row,
            replacement_info: replacement_info,
            replacement_dataset_rows: replacement_dataset_rows,
            replacement_mount_rows: replacement_mount_rows,
            replacement_child_row: replacement_child_row,
            replacement_descendant_mount: replacement_descendant_mount,
            replacement_external_mount: replacement_external_mount,
            descendant_mount: descendant_mount,
            external_mount: external_mount
          }

          expect(old_row.fetch('object_state')).to eq('soft_delete'), diagnostic.inspect
          expect(replacement_child_row).not_to be_nil, diagnostic.inspect
          expect(replacement_descendant_mount).not_to be_nil, diagnostic.inspect
          expect(replacement_descendant_mount.fetch('dataset_in_pool_id')).to eq(
            replacement_child_row.fetch('dataset_in_pool_id')
          ), diagnostic.inspect
          expect(replacement_descendant_mount.fetch('dataset_in_pool_id')).not_to eq(
            descendant_mount.fetch('dataset_in_pool_id')
          ), diagnostic.inspect
          expect(replacement_external_mount).to be_nil, diagnostic.inspect
          replacement_child_path = find_dataset_path_on_node(
            node2,
            replacement_child_row.fetch('full_name')
          )
          expect(read_dataset_text(
            node2,
            dataset_path: replacement_root_path,
            relative_path: 'root/root.txt'
          )).to include('replace descendant root sentinel'), diagnostic.inspect
          expect(read_dataset_text(
            node2,
            dataset_path: replacement_child_path,
            relative_path: 'payload/child.txt'
          )).to include('replace descendant child sentinel'), diagnostic.inspect
        end
      end
    '';
  }
)
