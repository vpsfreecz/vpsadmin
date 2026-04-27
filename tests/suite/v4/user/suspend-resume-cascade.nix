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
    name = "user-suspend-resume-cascade";
    description = ''
      Suspend and resume a user and verify VPS and DNS cascade state.
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

      describe 'user suspend and resume cascade', order: :defined do
        it 'suspends VPS and DNS state, then restores originally enabled state' do
          fixture = create_user_vps_export_dns_fixture(
            services,
            login: 'user-suspend-resume',
            password: 'secret123'
          )
          user_id = fixture.fetch('user_id')
          vps_id = fixture.fetch('vps').fetch('id')
          dns = fixture.fetch('dns')

          suspended = set_user_state(services, user_id: user_id, state: 'suspended')
          suspend_audit, = expect_chain_done(services, suspended, label: 'user suspend')

          wait_for_vps_on_node(services, vps_id: vps_id, node_id: node1_id, running: false)
          suspended_user = user_row(services, user_id)
          disabled_dns = dns_fixture_state(services, dns)

          expect(suspended_user.fetch('object_state')).to eq('suspended'), suspend_audit.inspect
          expect(disabled_dns.fetch('owned_zone_enabled')).to eq(false), suspend_audit.inspect
          expect(disabled_dns.fetch('user_record_enabled')).to eq(false), suspend_audit.inspect
          expect(disabled_dns.fetch('user_record_original_enabled')).to eq(true), suspend_audit.inspect

          resumed = set_user_state(services, user_id: user_id, state: 'active')
          resume_audit, = expect_chain_done(services, resumed, label: 'user resume')

          wait_for_vps_running(services, vps_id)
          resumed_user = user_row(services, user_id)
          enabled_dns = dns_fixture_state(services, dns)

          expect(resumed_user.fetch('object_state')).to eq('active'), resume_audit.inspect
          expect(enabled_dns.fetch('owned_zone_enabled')).to eq(true), resume_audit.inspect
          expect(enabled_dns.fetch('user_record_enabled')).to eq(true), resume_audit.inspect
        end
      end
    '';
  }
)
