{
  nameSuffix,
  machines,
  nodeMachines,
  description ? ''
    Boot the reusable ${nameSuffix} vpsAdmin cluster and verify API availability
    plus running nodectld on the nodes.
  '',
}:
{ pkgs, ... }:
{
  name = "cluster-${nameSuffix}";

  inherit description machines;

  tags = [
    "vpsadmin"
    "cluster"
    "node"
  ];

  testScript =
    let
      startList = builtins.concatStringsSep ", " ([ "services" ] ++ nodeMachines);
      nodectldChecks = builtins.concatStringsSep "\n\n" (
        map (node: ''
          it '${node} nodectld is running' do
            ${node}.wait_for_service('nodectld')
            ${node}.wait_until_succeeds("nodectl status | grep 'State: running'", timeout: 180)
          end
        '') nodeMachines
      );
    in
    ''
            before(:suite) do
              [${startList}].each(&:start)
            end

            describe 'cluster' do
              it 'services API responds' do
                services.wait_for_vpsadmin_api
              end

      ${nodectldChecks}
            end
    '';
}
