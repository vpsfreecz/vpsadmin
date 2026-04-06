{
  pkgs ? <nixpkgs>,
  system ? builtins.currentSystem,
  configuration ? null,
  testConfig ? { },
  suiteArgs ? { },
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
  "v4/storage/snapshot-download-full-archive"
  "v4/storage/snapshot-download-full-stream"
  "v4/storage/snapshot-download-incremental-stream"
  "v4/storage/snapshot-download-incremental-transfer"
  "v4/storage/snapshot-download-remove"
  "v4/storage/dataset-migrate-remote"
  "v4/storage/dataset-migrate-rsync-remote"
  "v4/storage/dataset-migrate-same-node"
  "v4/storage/dataset-migrate-same-node-with-exports"
  "v4/storage/dataset-migrate-retain-source"
  "v4/storage/dataset-migrate-with-exports"
  "v4/storage/group-snapshot"
  "v4/storage/topology-reconciliation"
  "v4/storage/topology-fixture-roundtrip"
  "v4/storage/topology-fixture-replay"
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
  "v4/vps/clone-same-node"
  "v4/vps/clone-remote"
  "v4/vps/clone-remote-consistent"
  "v4/vps/clone-different-owner"
  "v4/vps/clone-with-descendants-and-mounts"
  "v4/vps/migrate"
  "v4/vps/migrate-no-start"
  "v4/vps/migrate-skip-start"
  "v4/vps/migrate-with-data-check"
  "v4/vps/migrate-with-subdataset-mounts"
  "v4/vps/migrate-with-descendants"
  "v4/vps/migrate-interrupted-rsync"
  "v4/vps/migrate-retain-source"
  "v4/vps/replace-same-node"
  "v4/vps/replace-remote"
  "v4/vps/replace-no-start"
  "vpsadmin/services-up"
]
