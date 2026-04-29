import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeSeed = clusterSeed.nodes.node;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeSeed.id;
    };
  in
  {
    name = "admin-cluster-resource-package-assignment";

    description = ''
      Assign shared cluster-resource packages and verify user resource totals,
      including the from-personal package path.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "admin"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      before(:suite) do
        setup_admin_cluster(services, node)
      end

      describe 'cluster-resource package assignment', order: :defined do
        it 'updates totals and subtracts from personal packages' do
          env_id = 1
          user_id = admin_user_id

          before_shared = user_cluster_resource_values(
            services,
            user_id: user_id,
            environment_id: env_id
          )
          shared = create_shared_package_via_api_ruby(
            services,
            label: 'Admin shared package',
            values: { cpu: 2, memory: 512 }
          )
          assign_package_via_api_ruby(
            services,
            package_id: shared.fetch('id'),
            user_id: user_id,
            environment_id: env_id
          )
          after_shared = user_cluster_resource_values(
            services,
            user_id: user_id,
            environment_id: env_id
          )

          expect(after_shared.fetch('cpu')).to eq(before_shared.fetch('cpu') + 2)
          expect(after_shared.fetch('memory')).to eq(before_shared.fetch('memory') + 512)

          personal = create_personal_package_via_api_ruby(
            services,
            user_id: user_id,
            environment_id: env_id,
            values: { cpu: 10, memory: 1024 }
          )
          before_from_personal = user_cluster_resource_values(
            services,
            user_id: user_id,
            environment_id: env_id
          )
          shared_from_personal = create_shared_package_via_api_ruby(
            services,
            label: 'Admin shared from personal',
            values: { cpu: 4, memory: 256 }
          )
          assign_package_via_api_ruby(
            services,
            package_id: shared_from_personal.fetch('id'),
            user_id: user_id,
            environment_id: env_id,
            from_personal: true
          )
          after_from_personal = user_cluster_resource_values(
            services,
            user_id: user_id,
            environment_id: env_id
          )
          personal_items = package_item_values(
            services,
            package_id: personal.fetch('id')
          )

          expect(after_from_personal.fetch('cpu')).to eq(before_from_personal.fetch('cpu'))
          expect(after_from_personal.fetch('memory')).to eq(before_from_personal.fetch('memory'))
          expect(personal_items.fetch('cpu')).to eq(6)
          expect(personal_items.fetch('memory')).to eq(768)

          too_large = create_shared_package_via_api_ruby(
            services,
            label: 'Admin too large from personal',
            values: { cpu: 999 }
          )
          failure = assign_package_result_via_api_ruby(
            services,
            package_id: too_large.fetch('id'),
            user_id: user_id,
            environment_id: env_id,
            from_personal: true
          )

          expect(failure.fetch('ok')).to eq(false)
          expect(failure.fetch('error')).to eq(
            'VpsAdmin::API::Exceptions::UserResourceAllocationError'
          )
        end
      end
    '';
  }
)
