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
    name = "vps-clone-different-owner";

    description = ''
      Clone a VPS to another owner on the same node and verify the clone is
      chowned into the destination user namespace.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "vps"
      "storage"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      before(:suite) do
        [services, node].each(&:start)
        services.wait_for_vpsadmin_api
        wait_for_running_nodectld(node)
        wait_for_node_ready(services, node1_id)
        prepare_node_queues(node)
        services.unlock_transaction_signing_key(passphrase: 'test')
      end

      describe 'same-node VPS clone to a different owner', order: :defined do
        it 'creates the clone under the destination user namespace map' do
          src_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-clone-owner-src',
            filesystem: primary_pool_fs,
            role: 'hypervisor'
          )

          wait_for_pool_online(services, src_pool.fetch('id'))

          vps = create_vps(
            services,
            admin_user_id: admin_user_id,
            node_id: node1_id,
            hostname: 'vps-clone-owner-src'
          )

          src_info = nil
          wait_until_block_succeeds(name: "source dataset info for VPS #{vps.fetch('id')}") do
            src_info = dataset_info(services, vps.fetch('id'))
            !src_info.nil?
          end

          dst_pool_fs = 'tank/ct-clone-owner'
          dst_pool = create_pool(
            services,
            node_id: node1_id,
            label: 'vps-clone-owner-dst',
            filesystem: dst_pool_fs,
            role: 'hypervisor'
          )
          wait_for_pool_online(services, dst_pool.fetch('id'))

          services.vpsadminctl.succeeds(args: ['vps', 'start', vps.fetch('id').to_s])
          wait_for_vps_on_node(services, vps_id: vps.fetch('id'), node_id: node1_id, running: true)

          src_dataset_path = find_dataset_path_on_node(node, src_info.fetch('dataset_full_name'))
          write_dataset_text(
            node,
            dataset_path: src_dataset_path,
            relative_path: 'root/spec-owner.txt',
            content: "different owner clone sentinel\n"
          )

          dst_user = services.api_ruby_json(code: <<~RUBY)
            #{api_session_prelude(admin_user_id)}

            language = Language.order(:id).first
            env = Environment.find(1)
            login = "clone-owner-#{Time.now.to_i}"
            user = User.new(
              login: login,
              level: 1,
              full_name: 'Clone Owner',
              email: login + '@example.test',
              language: language
            )
            user.set_password('cloneOwnerPassword')
            user.save!

            EnvironmentUserConfig.find_or_create_by!(environment: env, user: user) do |cfg|
              cfg.can_create_vps = true
              cfg.can_destroy_vps = true
              cfg.vps_lifetime = 0
              cfg.max_vps_count = 10
              cfg.default = false
            end

            admin = User.find(#{Integer(admin_user_id)})
            admin.user_cluster_resources.where(environment: env).find_each do |ucr|
              UserClusterResource.find_or_create_by!(
                user: user,
                environment: env,
                cluster_resource: ucr.cluster_resource
              ) do |row|
                row.value = ucr.value
              end
            end

            block = UserNamespaceBlock.where(user_namespace_id: nil).order(:index).first
            userns = UserNamespace.create!(
              user: user,
              block_count: 1,
              offset: block.offset,
              size: block.size
            )
            block.update!(user_namespace: userns)

            userns_map = UserNamespaceMap.create_direct!(userns, 'Clone owner map')
            %i[uid gid].each do |kind|
              UserNamespaceMapEntry.create!(
                user_namespace_map: userns_map,
                kind: kind,
                vps_id: 0,
                ns_id: 0,
                count: userns.size
              )
            end

            puts JSON.dump(user_id: user.id, user_namespace_map_id: userns_map.id)
          RUBY

          response = vps_clone(
            services,
            admin_user_id: admin_user_id,
            vps_id: vps.fetch('id'),
            node_id: node1_id,
            user_id: dst_user.fetch('user_id'),
            stop: false
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

          clone_info = nil
          wait_until_block_succeeds(name: "clone dataset info for VPS #{response.fetch('cloned_vps_id')}") do
            clone_info = dataset_info(services, response.fetch('cloned_vps_id'))
            !clone_info.nil?
          end

          wait_for_vps_on_node(
            services,
            vps_id: response.fetch('cloned_vps_id'),
            node_id: node1_id,
            running: true
          )
          clone_row = vps_unscoped_row(services, response.fetch('cloned_vps_id'))
          clone_dataset_path = find_dataset_path_on_node(node, clone_info.fetch('dataset_full_name'))
          diagnostic = {
            chain_id: response.fetch('chain_id'),
            final_state: final_state,
            failure_details: failure_details,
            handles: handles,
            clone_row: clone_row,
            clone_info: clone_info,
            dst_user: dst_user
          }

          expect(handles).to include(tx_types(services).fetch('vps_chown')), diagnostic.inspect
          expect(clone_row.fetch('user_id')).to eq(dst_user.fetch('user_id')), diagnostic.inspect
          expect(clone_row.fetch('user_namespace_map_id')).to eq(dst_user.fetch('user_namespace_map_id')), diagnostic.inspect
          expect(read_dataset_text(
            node,
            dataset_path: clone_dataset_path,
            relative_path: 'root/spec-owner.txt'
          )).to include('different owner clone sentinel'), diagnostic.inspect
        end
      end
    '';
  }
)
