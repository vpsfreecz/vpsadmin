{
  pkgs,
  makeSystem,
  adminModule,
  exportedProfile,
}:
let
  inherit (pkgs) lib;
  common = {
    system.stateVersion = "26.05";
    networking.hostName = "maintenance-profile-test";
    networking.hosts."192.0.2.1" = [ "maintenance-profile-peer" ];
    vpsadmin.nodectld = {
      enable = true;
      settings = {
        vpsadmin = {
          node_id = 1;
          node_name = "maintenance-profile-test";
          transaction_public_key = "/etc/vpsadmin/transaction.key";
        };
      };
    };
    environment.etc."vpsadmin/transaction.key".text = "disposable module-check key";
  };
  rawPool = {
    boot.zfs.pools.tank = {
      install = false;
      properties."feature@block_cloning" = "disabled";
      datasets.proof.properties.mountpoint = "/mnt/maintenance-profile-proof";
    };
  };
  make =
    modules:
    makeSystem {
      modules = [
        adminModule
        common
      ]
      ++ modules;
    };
  directProfile = ../profiles/storage-maintenance.nix;
  ordinary = make [ rawPool ];
  maintenance = make [
    rawPool
    directProfile
  ];
  exported = make [
    rawPool
    exportedProfile
  ];
  directDefault = make [ directProfile ];
  exportedDefault = make [ exportedProfile ];
  osOnly = make [ { osctld.enable = false; } ];
  generatedRun = system: name: system.config.environment.etc."runit/services/${name}/run".source.text;
  assertionsHold = system: lib.all (entry: entry.assertion) system.config.assertions;
  valid =
    system:
    (builtins.tryEval (
      assert assertionsHold system;
      system.config.system.build.toplevel.drvPath
    )).success;
  refuses =
    module:
    !valid (make [
      rawPool
      directProfile
      module
    ]);
  cfg = maintenance.config;
  poolRun = generatedRun maintenance "pool-tank";
  runlevelLinks =
    system:
    lib.filter (name: lib.hasPrefix "runit/runsvdir/" name) (
      builtins.attrNames system.config.environment.etc
    );
  daemonLinks =
    system:
    lib.filter (name: lib.hasSuffix "/nodectld" name || lib.hasSuffix "/osctld" name) (
      runlevelLinks system
    );
  # Halt deliberately changes with the reviewed OS policy. Every other installed
  # package, including the retained Node and osctl tools, must remain identical.
  retainedPackages =
    system:
    map toString (
      lib.filter (package: lib.getName package != "halt") system.config.environment.systemPackages
    );
  haltPackage =
    system:
    let
      matching = lib.filter (
        package: lib.getName package == "halt"
      ) system.config.environment.systemPackages;
    in
    assert lib.assertMsg (builtins.length matching == 1) "expected one owning installed halt package";
    builtins.head matching;
  network = system: {
    inherit (system.config.networking) hostName hosts nameservers;
  };
  checks = {
    validOrdinary = valid ordinary;
    ordinaryStartup =
      ordinary.config.osctld.enable
      && ordinary.config.runit.services.osctld.runlevels == [ "default" ]
      && ordinary.config.runit.services.nodectld.runlevels == [ "default" ]
      && builtins.length (daemonLinks ordinary) == 2;
    osSettingDoesNotSelectAdminProfile =
      valid osOnly && osOnly.config.runit.services.nodectld.runlevels == [ "default" ];
    validDirectDefault = valid directDefault;
    validExportedDefault = valid exportedDefault;
    validDirectRawPool = valid maintenance;
    validExportedRawPool = valid exported;
    exportedEqualsDirect =
      cfg.vpsadmin.nodectld.settings == exported.config.vpsadmin.nodectld.settings
      && runlevelLinks maintenance == runlevelLinks exported
      && generatedRun maintenance "pool-tank" == generatedRun exported "pool-tank"
      && retainedPackages maintenance == retainedPackages exported;
    noDaemonLinks = daemonLinks maintenance == [ ] && daemonLinks exported == [ ];
    retainedDaemonDefinitions =
      generatedRun maintenance "nodectld" == generatedRun ordinary "nodectld"
      && generatedRun maintenance "osctld" == generatedRun ordinary "osctld";
    retainedSettings =
      cfg.vpsadmin.nodectld.settings == ordinary.config.vpsadmin.nodectld.settings
      && cfg.osctld.settings == ordinary.config.osctld.settings;
    retainedConfigAndKey =
      cfg.environment.etc."vpsadmin/nodectld.yml".source
      == ordinary.config.environment.etc."vpsadmin/nodectld.yml".source
      &&
        cfg.environment.etc."vpsadmin/transaction.key".source
        == ordinary.config.environment.etc."vpsadmin/transaction.key".source;
    retainedPackages = retainedPackages maintenance == retainedPackages ordinary;
    owningHaltPolicy =
      lib.all (system: lib.getName (haltPackage system) == "halt") [
        ordinary
        maintenance
        exported
        directDefault
        exportedDefault
        osOnly
      ]
      && toString (haltPackage ordinary) != toString (haltPackage maintenance)
      && lib.all (system: toString (haltPackage system) == toString (haltPackage maintenance)) [
        exported
        directDefault
        exportedDefault
        osOnly
      ];
    retainedNodeExecutables =
      toString maintenance.pkgs.nodectld == toString ordinary.pkgs.nodectld
      && toString maintenance.pkgs.nodectl == toString ordinary.pkgs.nodectl
      && lib.elem maintenance.pkgs.nodectl cfg.environment.systemPackages;
    retainedOsTools = lib.all (name: lib.elem maintenance.pkgs.${name} cfg.environment.systemPackages) [
      "osctl"
      "osup"
      "svctl"
    ];
    retainedHaltReason =
      cfg.runit.halt.reasonTemplates."10-vpsadmin-outages".source.text
      == ordinary.config.runit.halt.reasonTemplates."10-vpsadmin-outages".source.text;
    retainedNetwork = network maintenance == network ordinary;
    retainedPoolConfiguration = cfg.boot.zfs.pools.tank == ordinary.config.boot.zfs.pools.tank;
    rawPoolStartup =
      cfg.runit.services.pool-tank.oneShot
      && lib.hasInfix "zpool import" poolRun
      && lib.hasInfix "Mounting datasets..." poolRun
      && lib.hasInfix "feature@block_cloning=disabled" poolRun;
    noOsctlAssociation =
      !lib.any (text: lib.hasInfix text poolRun) [
        "waitForOsctld"
        "osctlEntityExists"
        "osctl pool"
        "org.vpsadminos.osctl:active"
      ];
    refusesDisabledIntegration = refuses { vpsadmin.nodectld.enable = lib.mkForce false; };
    refusesNodectldMembership = refuses {
      runit.services.nodectld.runlevels = lib.mkForce [ "rescue" ];
    };
    refusesOsctldMembership = refuses { runit.services.osctld.runlevels = lib.mkForce [ "rescue" ]; };
    refusesOsctldEnabled = refuses { osctld.enable = lib.mkForce true; };
    refusesDeclarativePool = refuses { osctl.pools.tank = { }; };
    refusesExportfs = refuses { osctl.exportfs.enable = true; };
    refusesPoolInstall = refuses { boot.zfs.pools.tank.install = lib.mkForce true; };
    refusesOomd = refuses { osctl.oomd.enable = true; };
    refusesOsctlExporter = refuses { services.prometheus.exporters.osctl.enable = true; };
  };
  failed = builtins.attrNames (lib.filterAttrs (_: result: !result) checks);
  projections = pkgs.writeText "storage-maintenance-profile-checks.json" (
    builtins.unsafeDiscardStringContext (builtins.toJSON checks)
  );
in
assert lib.assertMsg (
  failed == [ ]
) "storage-maintenance profile checks failed: ${lib.concatStringsSep ", " failed}";
pkgs.runCommand "storage-maintenance-profile" { } ''
  ordinary_script=$(readlink -f ${haltPackage ordinary}/bin/poweroff)
  maintenance_script=$(readlink -f ${haltPackage maintenance}/bin/poweroff)
  exported_script=$(readlink -f ${haltPackage exported}/bin/poweroff)
  grep -Fx "  OSCTLD_ENABLED = 'true' == 'true'" "$ordinary_script"
  grep -Fx "  OSCTLD_ENABLED = 'false' == 'true'" "$maintenance_script"
  cmp "$maintenance_script" "$exported_script"
  cp ${projections} "$out"
''
