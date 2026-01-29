let
  nodes = import ./test-nodes.nix;
in
nodes.mkClusterSeed {
  nodeRefs = {
    node = "node1";
  };
}
