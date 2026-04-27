import ../../../make-test.nix (
  { ... }@args:
  let
    seed = import ../../../../api/db/seeds/test.nix;
    adminUser = seed.adminUser;
    clusterSeed = import ../../../../api/db/seeds/test-1-node.nix;
    nodeId = clusterSeed.node.id;
    common = import ./common.nix {
      adminUserId = adminUser.id;
      node1Id = nodeId;
    };
  in
  {
    name = "user-soft-delete-revive-auth";
    description = ''
      Soft-delete a user, verify post-chain auth closure, then revive.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "user"
    ];

    machines = import ../../../machines/v4/cluster/1-node.nix args;

    testScript = common + ''
      configure_examples do |config|
        config.default_order = :defined
      end

      before(:suite) do
        setup_user_lifecycle_cluster(services, node)
      end

      describe 'user soft-delete, auth closure, and revive', order: :defined do
        it 'rejects auth after soft-delete and revives VPS/export state' do
          login = 'user-soft-revive'
          password = 'secret123'
          fixture = create_user_vps_export_dns_fixture(
            services,
            login: login,
            password: password
          )
          user_id = fixture.fetch('user_id')
          create_detached_token_session(services, user_id: user_id)

          before_auth = password_auth_result(services, login: login, password: password)
          expect(before_auth.fetch('authenticated')).to eq(true)

          deleted = set_user_state(services, user_id: user_id, state: 'soft_delete')
          delete_audit, = expect_chain_done(services, deleted, label: 'user soft delete')

          deleted_user = user_row(services, user_id)
          deleted_vps = first_user_vps(services, user_id)
          disabled_export = export_rows_for_user(services, user_id).first
          disabled_dns = dns_fixture_state(services, fixture.fetch('dns'))
          sessions = user_sessions_for(services, user_id)
          after_auth = password_auth_result(services, login: login, password: password)

          expect(deleted_user.fetch('object_state')).to eq('soft_delete'), delete_audit.inspect
          expect(deleted_vps.fetch('object_state')).to eq('soft_delete'), delete_audit.inspect
          expect(disabled_export.fetch('enabled')).to eq(false), delete_audit.inspect
          expect(disabled_dns.fetch('owned_zone_enabled')).to eq(false), delete_audit.inspect
          expect(disabled_dns.fetch('user_record_enabled')).to eq(false), delete_audit.inspect
          expect(sessions.all? { |session| session.fetch('token_id').nil? && session.fetch('closed_at') }).to eq(true)
          expect(after_auth.fetch('found')).to eq(false)

          revived = set_user_state(services, user_id: user_id, state: 'active')
          revive_audit, = expect_chain_done(services, revived, label: 'user revive')

          revived_user = user_row(services, user_id)
          revived_vps = first_user_vps(services, user_id)
          revived_export = export_rows_for_user(services, user_id).first

          expect(revived_user.fetch('object_state')).to eq('active'), revive_audit.inspect
          expect(revived_vps.fetch('object_state')).to eq('active'), revive_audit.inspect
          expect(revived_export.fetch('enabled')).to eq(true), revive_audit.inspect
        end
      end
    '';
  }
)
