let
  nodes = import ./test-nodes.nix;
in
nodes.mkClusterSeed {
  nodeRefs = {
    node1 = "node1";
    node2 = "node2";
  };
}
