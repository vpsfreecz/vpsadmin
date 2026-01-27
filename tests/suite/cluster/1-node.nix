import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    clusterTest = import ./common.nix;
  in
  clusterTest {
    nameSuffix = "1-node";
    description = ''
      Boot the reusable single-node vpsAdmin cluster and verify API availability
      plus running nodectld on the node.
    '';
    machines = import ../../machines/cluster/1-node.nix pkgs;
    nodeMachines = [ "node" ];
  } args
)
