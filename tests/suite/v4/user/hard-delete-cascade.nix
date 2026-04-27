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
    name = "user-hard-delete-cascade";
    description = ''
      Hard-delete a user and verify user-owned runtime and auth data cleanup.
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

      describe 'user hard-delete cascade', order: :defined do
        it 'removes credentials, namespaces, DNS, sessions, and user identity' do
          fixture = create_user_vps_export_dns_fixture(
            services,
            login: 'user-hard-delete',
            password: 'secret123'
          )
          user_id = fixture.fetch('user_id')
          vps_id = fixture.fetch('vps').fetch('id')
          create_detached_token_session(services, user_id: user_id)
          artifacts = create_hard_delete_user_objects(
            services,
            user_id: user_id,
            vps_id: vps_id
          )
          namespace = first_user_namespace(services, user_id)

          deleted = set_user_state(services, user_id: user_id, state: 'hard_delete')
          audit, = expect_chain_done(services, deleted, label: 'user hard delete', timeout: 900)

          user = user_row(services, user_id)
          vps = first_user_vps(services, user_id)
          sessions = user_sessions_for(services, user_id)
          dns = dns_fixture_state(services, fixture.fetch('dns'))
          counts = hard_delete_artifact_counts(services, artifacts)
          namespace_after = namespace_rows(
            services,
            user_namespace_id: namespace.fetch('user_namespace_id'),
            map_id: namespace.fetch('map_id'),
            block_ids: namespace.fetch('block_ids')
          )

          expect(user.fetch('object_state')).to eq('hard_delete'), audit.inspect
          expect(user.fetch('login')).to be_nil
          expect(user.fetch('password')).to eq('!')
          expect(vps.fetch('object_state')).to eq('hard_delete'), audit.inspect
          expect(sessions.all? { |session| session.fetch('token_id').nil? && session.fetch('closed_at') }).to eq(true)
          expect(dns.fetch('owned_zone_exists')).to eq(false)
          expect(dns.fetch('user_record_exists')).to eq(false)
          expect(counts.values).to all(eq(0))
          expect(namespace_after.fetch('user_namespace_count')).to eq(0)
          expect(namespace_after.fetch('map_count')).to eq(0)
          expect(namespace_after.fetch('block_user_namespace_ids')).to all(be_nil)
        end
      end
    '';
  }
)
