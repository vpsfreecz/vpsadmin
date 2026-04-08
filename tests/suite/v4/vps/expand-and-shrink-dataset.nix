import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ../storage/remote-common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
      node2Id = nodeSeed.id;
      manageCluster = false;
    };
  in
  {
    name = "vps-expand-and-shrink-dataset";

    description = ''
      Expand a VPS root dataset, expand it again, and shrink it back while
      checking DB metadata, history rows, and on-node refquota changes.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      def zfs_refquota_bytes(machine, dataset_path)
        _, output = machine.succeeds(
          "zfs get -Hp -o value refquota #{Shellwords.escape(dataset_path)}",
          timeout: 60
        )
        output.to_i
      end

      def mib_to_bytes(value)
        Integer(value) * 1024 * 1024
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'dataset expansion lifecycle', order: :defined do
        it 'expands, expands again, and shrinks the VPS root dataset' do
          first_added = 1024
          second_added = 2048

          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-expand-shrink',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-expand-shrink'
          )

          info = nil
          wait_until_block_succeeds(name: "dataset info available for VPS #{vps.fetch('id')}") do
            info = dataset_info(services, vps.fetch('id'))
            !info.nil?
          end

          dataset_path = "#{info.fetch('pool_filesystem')}/#{info.fetch('dataset_full_name')}"
          original_refquota = info.fetch('refquota')
          original_zfs_refquota = zfs_refquota_bytes(node, dataset_path)

          expand_response = create_dataset_expansion(
            services,
            admin_user_id: admin_user_id,
            dataset_id: info.fetch('dataset_id'),
            added_space: first_added,
            enable_notifications: false
          )
          expand_audit, = expect_chain_done(
            services,
            expand_response,
            label: 'dataset-expand',
            expected_handles: [tx_types(services).fetch('storage_set_dataset')]
          )

          dataset_row_after_expand = services.mysql_json_rows(sql: <<~SQL).first
            SELECT JSON_OBJECT('dataset_expansion_id', dataset_expansion_id)
            FROM datasets
            WHERE id = #{Integer(info.fetch('dataset_id'))}
            LIMIT 1
          SQL
          expansion_after_expand = dataset_expansion_row(
            services,
            expand_response.fetch('dataset_expansion_id')
          )
          history_after_expand = dataset_expansion_history_rows(
            services,
            expand_response.fetch('dataset_expansion_id')
          )
          dip_after_expand = dataset_in_pool_row(services, info.fetch('dataset_in_pool_id'))
          zfs_after_expand = zfs_refquota_bytes(node, dataset_path)

          expect(dip_after_expand.fetch('refquota')).to eq(original_refquota + first_added), expand_audit.inspect
          expect(zfs_after_expand).to eq(
            original_zfs_refquota + mib_to_bytes(first_added)
          ), expand_audit.inspect
          expect(dataset_row_after_expand.fetch('dataset_expansion_id')).to eq(
            expand_response.fetch('dataset_expansion_id')
          ), expand_audit.inspect
          expect(expansion_after_expand.fetch('original_refquota')).to eq(original_refquota), expand_audit.inspect
          expect(expansion_after_expand.fetch('added_space')).to eq(first_added), expand_audit.inspect
          expect(history_after_expand.size).to eq(1), expand_audit.inspect
          expect(history_after_expand.first.fetch('added_space')).to eq(first_added), expand_audit.inspect
          expect(history_after_expand.first.fetch('original_refquota')).to eq(
            original_refquota
          ), expand_audit.inspect
          expect(history_after_expand.first.fetch('new_refquota')).to eq(
            original_refquota + first_added
          ), expand_audit.inspect

          again_response = create_dataset_expansion_again(
            services,
            admin_user_id: admin_user_id,
            dataset_expansion_id: expand_response.fetch('dataset_expansion_id'),
            added_space: second_added
          )
          again_audit, = expect_chain_done(
            services,
            again_response,
            label: 'dataset-expand-again',
            expected_handles: [tx_types(services).fetch('storage_set_dataset')]
          )

          expansion_after_again = dataset_expansion_row(
            services,
            expand_response.fetch('dataset_expansion_id')
          )
          history_after_again = dataset_expansion_history_rows(
            services,
            expand_response.fetch('dataset_expansion_id')
          )
          dip_after_again = dataset_in_pool_row(services, info.fetch('dataset_in_pool_id'))
          zfs_after_again = zfs_refquota_bytes(node, dataset_path)
          last_history = history_after_again.last

          expect(dip_after_again.fetch('refquota')).to eq(
            original_refquota + first_added + second_added
          ), again_audit.inspect
          expect(zfs_after_again).to eq(
            original_zfs_refquota + mib_to_bytes(first_added + second_added)
          ), again_audit.inspect
          expect(expansion_after_again.fetch('added_space')).to eq(
            first_added + second_added
          ), again_audit.inspect
          expect(history_after_again.size).to eq(2), again_audit.inspect
          expect(last_history.fetch('added_space')).to eq(second_added), again_audit.inspect
          expect(last_history.fetch('original_refquota')).to eq(
            original_refquota + first_added
          ), again_audit.inspect
          expect(last_history.fetch('new_refquota')).to eq(
            original_refquota + first_added + second_added
          ), again_audit.inspect

          shrink_response = shrink_dataset_expansion(
            services,
            admin_user_id: admin_user_id,
            dataset_expansion_id: expand_response.fetch('dataset_expansion_id')
          )
          shrink_audit, = expect_chain_done(
            services,
            shrink_response,
            label: 'dataset-shrink',
            expected_handles: [tx_types(services).fetch('storage_set_dataset')]
          )

          dataset_row_after_shrink = services.mysql_json_rows(sql: <<~SQL).first
            SELECT JSON_OBJECT('dataset_expansion_id', dataset_expansion_id)
            FROM datasets
            WHERE id = #{Integer(info.fetch('dataset_id'))}
            LIMIT 1
          SQL
          expansion_after_shrink = dataset_expansion_row(
            services,
            expand_response.fetch('dataset_expansion_id')
          )
          dip_after_shrink = dataset_in_pool_row(services, info.fetch('dataset_in_pool_id'))
          zfs_after_shrink = zfs_refquota_bytes(node, dataset_path)

          expect(dip_after_shrink.fetch('refquota')).to eq(original_refquota), shrink_audit.inspect
          expect(zfs_after_shrink).to eq(original_zfs_refquota), shrink_audit.inspect
          expect(dataset_row_after_shrink.fetch('dataset_expansion_id')).to be_nil, shrink_audit.inspect
          expect(expansion_after_shrink.fetch('state')).to eq('resolved'), shrink_audit.inspect
        end
      end
    '';
  }
)
