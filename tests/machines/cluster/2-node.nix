_pkgs:
let
  seedPath = ../../../api/db/seeds/test-2-node.nix;
  seed = import seedPath;
  mkCluster = import ./mk-cluster.nix;
in
mkCluster {
  inherit seedPath seed;
  nodes = {
    node1 = seed.node1;
    node2 = seed.node2;
  };
} _pkgs
