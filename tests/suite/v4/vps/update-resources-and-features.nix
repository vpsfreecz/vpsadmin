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
    name = "vps-update-resources-and-features";

    description = ''
      Update VPS resources and features on a running container and verify the
      resulting transaction chains plus the DB/runtime outcomes.
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

      def expect_vps_chain_done(services, response, label:, expected_handles: [])
        final_state = wait_for_vps_chain_done(services, response.fetch('chain_id'))
        handles = chain_transactions(services, response.fetch('chain_id')).map { |row| row.fetch('handle') }
        audit = {
          chain_id: response.fetch('chain_id'),
          final_state: final_state,
          handles: handles,
          failure_details: chain_failure_details(services, response.fetch('chain_id'))
        }

        expect(final_state).to eq(services.class::CHAIN_STATES[:done]), "#{label}: #{audit.inspect}"

        expected_handles.each do |handle|
          expect(handles).to include(handle), "#{label}: #{audit.inspect}"
        end

        audit
      end

      def set_vps_features(services, admin_user_id:, vps_id:, features:)
        features_json = features.to_json

        services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          vps = Vps.find(#{Integer(vps_id)})
          chain = VpsAdmin::API::Operations::Vps::SetFeatures.run(
            vps,
            JSON.parse(#{features_json.inspect}, symbolize_names: true)
          )

          puts JSON.dump(chain_id: chain.id)
        RUBY
      end

      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'resource and feature updates', order: :defined do
        it 'updates resources, toggles features, and keeps the VPS running' do
          pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-update',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-update'
          )

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          update_response = vps_update(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            attrs: {
              cpu: 2,
              memory: 2048,
              swap: 512,
              cpu_limit: 250
            }
          )
          expect_vps_chain_done(
            services,
            update_response,
            label: 'resource-update',
            expected_handles: [tx_types(services).fetch('vps_resources')]
          )

          resource_rows = vps_resource_uses(services, vps.fetch('id')).each_with_object({}) do |row, acc|
            acc[row.fetch('resource')] = row.fetch('value')
          end
          row_after_update = vps_row(services, vps.fetch('id'))

          expect(resource_rows).to include(
            'cpu' => 2,
            'memory' => 2048,
            'swap' => 512
          )
          expect(row_after_update.fetch('cpu_limit')).to eq(250)

          _, memory_limit = node.succeeds(
            "osctl ct show -H -o memory_limit #{Integer(vps.fetch('id'))}",
            timeout: 120
          )
          _, swap_limit = node.succeeds(
            "osctl ct show -H -o swap_limit #{Integer(vps.fetch('id'))}",
            timeout: 120
          )
          _, effective_cpu_limit = node.succeeds(
            "osctl ct show -H -o cpu_limit #{Integer(vps.fetch('id'))}",
            timeout: 120
          )

          expect(memory_limit.strip).to eq('2.0G')
          expect(swap_limit.strip).to eq('512.0M')
          expect(effective_cpu_limit.strip).to eq('200')

          feature_response = set_vps_features(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            features: {
              lxc: true,
              impermanence: true
            }
          )
          expect_vps_chain_done(
            services,
            feature_response,
            label: 'feature-update',
            expected_handles: [tx_types(services).fetch('vps_features')]
          )

          feature_rows = vps_feature_rows(services, vps.fetch('id')).to_h do |feature|
            [feature.fetch('name'), feature.fetch('enabled')]
          end

          expect(feature_rows).to include(
            'lxc' => 1,
            'impermanence' => 1
          )

          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)
        end
      end
    '';
  }
)
