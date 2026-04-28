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
    name = "tasks-auth-session-housekeeping";

    description = ''
      Run auth and user-session housekeeping through fresh rake processes and
      verify expired auth/session rows are cleaned up and failed logins are
      reported.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "tasks"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        setup_tasks_cluster(services, node, pool_label: 'tasks-auth')
      end

      describe 'auth and session housekeeping tasks', order: :defined do
        it 'cleans expired auth state and reports failed logins' do
          fixture = create_auth_session_housekeeping_fixture(services)

          run_api_rake_task(
            services,
            task: 'vpsadmin:auth:close_expired',
            env: { EXECUTE: 'yes' }
          )
          run_api_rake_task(
            services,
            task: 'vpsadmin:user_session:close_expired',
            env: { EXECUTE: 'yes' }
          )
          run_api_rake_task(
            services,
            task: 'vpsadmin:auth:report_failed_logins',
            env: { EXECUTE: 'yes' }
          )

          rows = auth_session_housekeeping_rows(services, fixture)
          expect(rows.fetch('auth_token_exists')).to eq(false)
          expect(rows.fetch('detached_oauth_exists')).to eq(false)
          expect(rows.fetch('auth_challenge_exists')).to eq(false)
          expect(rows.fetch('closing_session_closed')).to eq(true)
          expect(rows.fetch('closing_session_token_id')).to be_nil
          expect(rows.fetch('refreshable_session_closed')).to eq(false)
          expect(rows.fetch('refreshable_session_token_id')).to be_nil
          expect(rows.fetch('refreshable_oauth_refresh_token_id')).not_to be_nil
          expect(rows.fetch('sso_token_id')).to be_nil
          expect(rows.fetch('device_token_id')).to be_nil
          expect(rows.fetch('reported_failed_login_count')).to eq(2)
          expect(rows.fetch('report_chain_count')).to be >= 1
        end
      end
    '';
  }
)
