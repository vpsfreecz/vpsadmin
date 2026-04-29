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
    name = "admin-environment-defaults-propagation";

    description = ''
      Update environment defaults and verify only default user config rows
      inherit the new values.
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

      describe 'environment default propagation', order: :defined do
        it 'updates default user config rows only' do
          fixture = services.api_ruby_json(code: <<~RUBY)
            env = Environment.find(1)
            env.update!(
              can_create_vps: false,
              can_destroy_vps: false,
              vps_lifetime: 7,
              max_vps_count: 1
            )

            default_user = User.find(#{admin_user_id})
            custom_user = User.find_or_initialize_by(login: 'admin-env-custom')
            custom_user.assign_attributes(
              full_name: 'Admin Env Custom',
              email: 'admin-env-custom@example.test',
              level: 1,
              language: Language.first
            )
            custom_user.set_password('secret')
            custom_user.save!

            default_cfg = EnvironmentUserConfig.find_or_initialize_by(
              environment: env,
              user: default_user
            )
            default_cfg.assign_attributes(
              default: true,
              can_create_vps: false,
              can_destroy_vps: false,
              vps_lifetime: 7,
              max_vps_count: 1
            )
            default_cfg.save!

            custom_cfg = EnvironmentUserConfig.find_or_initialize_by(
              environment: env,
              user: custom_user
            )
            custom_cfg.assign_attributes(
              default: false,
              can_create_vps: false,
              can_destroy_vps: false,
              vps_lifetime: 99,
              max_vps_count: 99
            )
            custom_cfg.save!

            VpsAdmin::API::Operations::Environment::Update.run(
              env,
              {
                can_create_vps: true,
                can_destroy_vps: true,
                vps_lifetime: 30,
                max_vps_count: 3
              }
            )

            puts JSON.dump(
              env_id: env.id,
              default_user_id: default_user.id,
              custom_user_id: custom_user.id
            )
          RUBY

          env = environment_defaults_row(services, fixture.fetch('env_id'))
          default_cfg = environment_user_configs(
            services,
            env_id: fixture.fetch('env_id'),
            user_id: fixture.fetch('default_user_id')
          ).first
          custom_cfg = environment_user_configs(
            services,
            env_id: fixture.fetch('env_id'),
            user_id: fixture.fetch('custom_user_id')
          ).first

          expect(json_true?(env.fetch('can_create_vps'))).to eq(true)
          expect(json_true?(env.fetch('can_destroy_vps'))).to eq(true)
          expect(env.fetch('vps_lifetime')).to eq(30)
          expect(env.fetch('max_vps_count')).to eq(3)

          expect(json_true?(default_cfg.fetch('default'))).to eq(true)
          expect(json_true?(default_cfg.fetch('can_create_vps'))).to eq(true)
          expect(json_true?(default_cfg.fetch('can_destroy_vps'))).to eq(true)
          expect(default_cfg.fetch('vps_lifetime')).to eq(30)
          expect(default_cfg.fetch('max_vps_count')).to eq(3)

          expect(json_true?(custom_cfg.fetch('default'))).to eq(false)
          expect(json_true?(custom_cfg.fetch('can_create_vps'))).to eq(false)
          expect(json_true?(custom_cfg.fetch('can_destroy_vps'))).to eq(false)
          expect(custom_cfg.fetch('vps_lifetime')).to eq(99)
          expect(custom_cfg.fetch('max_vps_count')).to eq(99)
        end
      end
    '';
  }
)
