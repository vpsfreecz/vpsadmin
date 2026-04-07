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
    name = "vps-swap-across-locations";

    description = ''
      Swap two VPSes across locations and verify node assignments, datasets,
      rootfs contents, and IP ownership after the swap completes.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
    ];

    machines = import ../../../machines/v4/cluster/2-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      def expect_vps_chain_done(services, response, label:, expected_handles: [])
        final_state = wait_for_vps_chain_done(services, response.fetch('chain_id'), timeout: 600)
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

      def move_node2_to_other_location(services, admin_user_id:, node_id:)
        services.api_ruby_json(code: <<~RUBY)
          #{api_session_prelude(admin_user_id)}

          env = Environment.find(1)
          location = Location.find_or_initialize_by(label: 'swap-location-b')
          location.assign_attributes(
            environment: env,
            domain: 'lab-b',
            description: 'Swap location B',
            remote_console_server: 'http://console.vpsadmin.test',
            has_ipv6: false
          )
          location.save! if location.changed?

          node = Node.find(#{Integer(node_id)})
          node.update!(location: location)

          puts JSON.dump(location_id: location.id, node_id: node.id)
        RUBY
      end

      before(:suite) do
        [services, node1, node2].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node1)
        wait_for_running_nodectld(node2)
        wait_for_node_ready(services, node1_id)
        wait_for_node_ready(services, node2_id)
        prepare_node_queues(node1)
        prepare_node_queues(node2)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'swap across locations', order: :defined do
        it 'moves both VPSes to the opposite nodes and swaps their IP assignments' do
          move_node2_to_other_location(
            services,
            admin_user_id: admin_user_id,
            node_id: node2_id
          )

          pool1 = create_pool(
            services,
            node_id: node1_id,
            label: 'swap-node1',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )
          pool2 = create_pool(
            services,
            node_id: node2_id,
            label: 'swap-node2',
            filesystem: 'tank/node2-ct',
            role: 'hypervisor'
          )
          wait_for_pool_online(services, pool1.fetch('id'))
          wait_for_pool_online(services, pool2.fetch('id'))

          pool1_key = generate_pool_migration_key(node1, pool_name: primary_pool_fs.split('/').first)
          pool2_key = generate_pool_migration_key(node2, pool_name: pool2.fetch('filesystem').split('/').first)

          set_pool_migration_public_key(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool1.fetch('id'),
            public_key: pool1_key
          )
          set_pool_migration_public_key(
            services,
            admin_user_id: admin_user_id,
            pool_id: pool2.fetch('id'),
            public_key: pool2_key
          )

          primary = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-swap-primary'
          )
          secondary = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node2_id,
            hostname: 'vps-swap-secondary'
          )

          services.vpsadminctl.succeeds(args: ['vps', 'start', primary.fetch('id').to_s])
          services.vpsadminctl.succeeds(args: ['vps', 'start', secondary.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: primary.fetch('id'), node_id: node1_id, running: true)
          wait_for_vps_on_node(services, vps_id: secondary.fetch('id'), node_id: node2_id, running: true)

          vps_exec(
            node1,
            vps_id: primary.fetch('id'),
            command: "printf 'primary-sentinel\\n' > /root/swap-sentinel.txt",
            timeout: 120
          )
          vps_exec(
            node2,
            vps_id: secondary.fetch('id'),
            command: "printf 'secondary-sentinel\\n' > /root/swap-sentinel.txt",
            timeout: 120
          )

          attach_test_vps_ip(
            services,
            admin_user_id: admin_user_id,
            vps_id: primary.fetch('id'),
            addr: '198.51.100.10'
          )
          attach_test_vps_ip(
            services,
            admin_user_id: admin_user_id,
            vps_id: secondary.fetch('id'),
            addr: '198.51.100.20'
          )

          response = vps_swap(
            services,
            admin_user_id: admin_user_id,
            vps_id: primary.fetch('id'),
            other_vps_id: secondary.fetch('id'),
            resources: false,
            hostname: false,
            expirations: false
          )
          expect_vps_chain_done(
            services,
            response,
            label: 'swap',
            expected_handles: [
              tx_types(services).fetch('vps_send_config'),
              tx_types(services).fetch('vps_send_rootfs'),
              tx_types(services).fetch('vps_send_state'),
              tx_types(services).fetch('vps_stop')
            ]
          )

          wait_for_vps_on_node(services, vps_id: primary.fetch('id'), node_id: node2_id, running: true)
          wait_for_vps_on_node(services, vps_id: secondary.fetch('id'), node_id: node1_id, running: true)

          primary_row = vps_row(services, primary.fetch('id'))
          secondary_row = vps_row(services, secondary.fetch('id'))

          expect(primary_row.fetch('node_id')).to eq(node2_id)
          expect(secondary_row.fetch('node_id')).to eq(node1_id)

          primary_ips = vps_ip_rows(services, primary.fetch('id')).map { |row| row.fetch('addr') }
          secondary_ips = vps_ip_rows(services, secondary.fetch('id')).map { |row| row.fetch('addr') }
          expect(primary_ips).to eq(['198.51.100.20'])
          expect(secondary_ips).to eq(['198.51.100.10'])

          primary_datasets = vps_dataset_rows(services, primary.fetch('id'))
          secondary_datasets = vps_dataset_rows(services, secondary.fetch('id'))
          expect(primary_datasets.map { |row| row.fetch('pool_id') }.uniq).to eq([pool2.fetch('id')])
          expect(secondary_datasets.map { |row| row.fetch('pool_id') }.uniq).to eq([pool1.fetch('id')])

          primary_output = nil
          secondary_output = nil

          wait_until_block_succeeds(name: 'swapped VPSes keep their original rootfs contents') do
            _, primary_output = vps_exec(
              node2,
              vps_id: primary.fetch('id'),
              command: 'cat /root/swap-sentinel.txt',
              timeout: 120
            )
            _, secondary_output = vps_exec(
              node1,
              vps_id: secondary.fetch('id'),
              command: 'cat /root/swap-sentinel.txt',
              timeout: 120
            )

            primary_output.include?('primary-sentinel') && secondary_output.include?('secondary-sentinel')
          end

          expect(primary_output).to include('primary-sentinel')
          expect(secondary_output).to include('secondary-sentinel')
        end
      end
    '';
  }
)
