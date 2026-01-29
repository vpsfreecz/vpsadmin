_pkgs:
let
  seedPath = ../../../api/db/seeds/test-2-node.nix;
  clusterSeed = import seedPath;
  mkCluster = import ./mk-cluster.nix;
in
mkCluster {
  inherit seedPath;
  seed = clusterSeed;
  nodes = clusterSeed.nodes;
} _pkgs
