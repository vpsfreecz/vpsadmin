import ../../make-test.nix (
  { pkgs, ... }@args:
  let
    clusterTest = import ./common.nix;
  in
  clusterTest {
    nameSuffix = "2-node";
    description = ''
      Boot the reusable two-node vpsAdmin cluster and verify API availability
      plus running nodectld on both nodes.
    '';
    machines = import ../../machines/cluster/2-node.nix pkgs;
    nodeMachines = [
      "node1"
      "node2"
    ];
  } args
)
