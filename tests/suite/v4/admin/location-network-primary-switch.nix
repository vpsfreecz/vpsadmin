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
    name = "admin-location-network-primary-switch";

    description = ''
      Switch a network primary link between locations and verify deleting the
      primary link clears the network primary location.
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

      describe 'location-network primary switch', order: :defined do
        it 'promotes another location and clears primary on delete' do
          fixture = create_location_network_primary_fixture(services)

          switch_location_network_primary(
            services,
            location_network_id: fixture.fetch('second_location_network_id')
          )

          rows = location_network_rows(
            services,
            network_id: fixture.fetch('network_id')
          )
          primary_rows = rows.select { |row| json_true?(row.fetch('primary')) }
          network = network_row(services, network_id: fixture.fetch('network_id'))

          expect(primary_rows.size).to eq(1)
          expect(primary_rows.first.fetch('id')).to eq(
            fixture.fetch('second_location_network_id')
          )
          expect(primary_rows.first.fetch('location_id')).to eq(
            fixture.fetch('second_location_id')
          )
          expect(network.fetch('primary_location_id')).to eq(
            fixture.fetch('second_location_id')
          )

          delete_location_network_via_api_ruby(
            services,
            location_network_id: fixture.fetch('second_location_network_id')
          )
          rows = location_network_rows(
            services,
            network_id: fixture.fetch('network_id')
          )
          network = network_row(services, network_id: fixture.fetch('network_id'))

          expect(rows.any? { |row| json_true?(row.fetch('primary')) }).to eq(false)
          expect(network.fetch('primary_location_id')).to be_nil
        end
      end
    '';
  }
)
