import ../../../make-test.nix (
  { pkgs, ... }@args:
  let
    fixtureDir = ./fixtures;
    fixtureNames = builtins.filter (name: builtins.match ".*\\.json" name != null) (
      builtins.attrNames (builtins.readDir fixtureDir)
    );
    fixturePaths = map (name: "${fixtureDir}/${name}") fixtureNames;
    common = import ./remote-common.nix {
      manageCluster = false;
    };
  in
  {
    name = "storage-topology-fixture-replay";

    description = ''
      Load committed storage topology fixtures and verify that normalization and
      delete-order diagnostics stay stable when replayed offline.
    '';

    tags = [
      "ci"
      "vpsadmin"
      "storage"
    ];

    machines = { };

    testScript = common + ''
      fixture_paths = ${builtins.toJSON fixturePaths}

      describe 'topology fixture replay', order: :defined do
        it 'has committed fixtures to replay' do
          expect(fixture_paths).not_to eq([])
        end

        fixture_paths.each do |path|
          it "validates #{File.basename(path)}" do
            fixture = load_topology_fixture(path)
            contract = validate_topology_fixture!(fixture)

            expect(fixture.fetch('diagnostic')).to eq(
              delete_order_diagnostic(fixture.fetch('report'))
            )
            expect(contract).to include('leaf_sets_match')
          end
        end
      end
    '';
  }
)
