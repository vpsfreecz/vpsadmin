{
  pkgs ? <nixpkgs>,
  system ? builtins.currentSystem,
  configuration ? null,
  testConfig ? { },
  suiteArgs ? { },
  configuration ? null,
  testConfig ? { },
}:
let
  vpsadminosPath = suiteArgs.vpsadminosPath or (throw "suiteArgs.vpsadminosPath is required");
  nixpkgs = import pkgs { inherit system; };
  lib = nixpkgs.lib;
  testLib = import (vpsadminosPath + "/test-runner/nix/lib.nix") {
    inherit
      pkgs
      system
      lib
      configuration
      testConfig
      suiteArgs
      configuration
      testConfig
      ;
    suitePath = ./suite;
  };
in
testLib.makeTests [
  "v4/cluster/1-node"
  "v4/cluster/2-node"
  "v4/node/register"
  "v4/storage/backup-full-incremental"
  "v4/storage/backup-full-incremental-remote"
  "v4/storage/rollback-from-backup"
  "v4/storage/rollback-from-remote-backup"
  "v4/storage/restore-after-reinstall-remote"
  "v4/storage/rollback-with-descendants"
  "v4/storage/restore-after-reinstall-with-descendants-remote"
  "v4/storage/backup-remote-interrupted-send"
  "v4/storage/backup-remote-interrupted-recv"
  "v4/storage/restore-remote-interrupted-recv"
  "v4/storage/topology-reconciliation"
  "v4/storage/topology-fixture-roundtrip"
  "v4/storage/history-divergence-new-tree"
  "v4/storage/rollback-across-trees"
  "v4/storage/backup-multiple-destinations-remote"
  "v4/storage/backup-multiple-destinations-diverged-remote"
  "v4/storage/repeated-rollback-branching"
  "v4/storage/branching-rotation"
  "v4/storage/source-rotation-after-backup-prune"
  "v4/storage/branching-destroy"
  "v4/storage/dataset-destroy-after-rollback-history"
  "v4/storage/dataset-destroy-complex-history"
  "v4/storage/complex-destroy-order"
  "v4/storage/complex-rotation-order-pending"
  "v4/storage/vps-hard-delete-after-complex-history"
  "v4/storage/vps-hard-delete-complex-history-with-descendants"
  "v4/tx/chain-lifecycle"
  "v4/tx/invalid-signature"
  "v4/tx/manual-confirmations"
  "v4/tx/rollback-state-machine"
  "v4/tx/keep-going-final-state"
  "v4/tx/release-retry-resolve"
  "v4/vps/create"
  "v4/vps/migrate"
  "vpsadmin/services-up"
]
