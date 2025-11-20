{
  config,
  pkgs,
  lib,
}:
let
  stage2Config = import <nixpkgs/nixos/lib/eval-config.nix> {
    # pkgs are not inherited in order to avoid overlays from vpsAdminOS, which
    # are not compatible with a NixOS system.
    pkgs = import <nixpkgs> { };

    modules = [
      (
        {
          config,
          pkgs,
          lib,
          ...
        }:
        {
          nixpkgs.overlays = (import ../../../overlays) ++ [ (import <vpsadminos/os/overlays/packages.nix>) ];

          boot.kernelPackages = pkgs.linuxPackagesFor (
            pkgs.linuxPackages.kernel.override {
              structuredExtraConfig = with lib.kernel; {
                EXT4_FS = yes;
                OVERLAY_FS = yes;

                HW_RANDOM = yes;
                HW_RANDOM_VIRTIO = yes;

                VIRTIO = yes;
                VIRTIO_BLK = yes;
                VIRTIO_CONSOLE = yes;
                VIRTIO_NET = yes;
                VIRTIO_PCI = yes;

                CPUSETS_V1 = yes;
                MEMCG_V1 = yes;
              };
            }
          );

          fileSystems."/" = {
            device = "/dev/vda";
            fsType = "ext4";
            # autoFormat = true;
          };

          boot.loader.grub.device = "/dev/vda";

          environment.systemPackages = with pkgs; [
            btrfs-progs
            distconfig
            e2fsprogs
            lxc
            qemu
            qemuGaRunner
            strace
          ];

          # Wrappers are needed for login. Since we do not run systemd and its
          # services, we make it a part of profile activation.
          system.activationScripts.wrappers =
            lib.stringAfter
              [
                "specialfs"
                "users"
              ]
              ''
                mkdir -p $(dirname ${config.security.wrapperDir})
                ${config.systemd.services.suid-sgid-wrappers.script}
              '';

          networking.hostName = "stage-2";

          documentation = {
            enable = false;
            dev.enable = false;
            info.enable = false;
            man.enable = false;
            nixos.enable = false;
          };

          fonts.fontconfig.enable = false;

          system.stateVersion = "${lib.trivial.release}";
        }
      )
    ];
  };

  kernel = stage2Config.config.boot.kernelPackages.kernel;

  udev = pkgs.eudev;

  udevRules = pkgs.runCommand "udev-rules" { } ''
    mkdir -p $out

    cp -v ${udev}/var/lib/udev/rules.d/60-persistent-storage.rules $out/
    cp -v ${udev}/var/lib/udev/rules.d/80-drivers.rules $out/

    cat <<'EOF' > $out/90-virtio-ports.rules
    SUBSYSTEM=="virtio-ports", KERNEL=="vport*", ATTR{name}=="?*", SYMLINK+="virtio-ports/$attr{name}"
    EOF
  '';

  udevHwdb = stage2Config.config.environment.etc."udev/hwdb.bin".source;

  bootStage1 = pkgs.replaceVarsWith {
    src = ./stage-1-init.sh;
    isExecutable = true;
    replacements = {
      shell = "${pkgs.bash}/bin/bash";
      path = stage2Config.config.system.path;
      bootStage2 = builtins.unsafeDiscardStringContext bootStage2;
    };
  };

  bootStage2 = pkgs.replaceVarsWith {
    src = ./stage-2-init.sh;
    isExecutable = true;
    replacements = {
      shell = "${pkgs.bash}/bin/bash";
      systemConfig = stage2Config.config.system.build.toplevel;
      path = stage2Config.config.system.path;
      inherit (stage2Config.config.networking) hostName;
      inherit udev udevRules udevHwdb;
      ctstartmenu = pkgs.ctstartmenu;
    };
  };

  rootDirs = pkgs.runCommand "root-dirs" { } ''
    mkdir $out
    cd $out
    mkdir rootfs image overlay
  '';

  qemuGaRunner = pkgs.writeScriptBin "qemu-ga-runner.sh" ''
    #!${pkgs.bash}/bin/bash

    echo -1000 > /proc/$$/oom_score_adj

    while true ; do
      qemu-ga -m virtio-serial
      echo "QEMU Guest Agent exited with status $?, restarting"
      sleep 5
    done

    exit 0
  '';

  stage2Image = import <nixpkgs/nixos/lib/make-disk-image.nix> {
    inherit pkgs lib;
    inherit (stage2Config) config;
    additionalPaths = [
      bootStage2
    ];
    contents = [
      {
        source = bootStage1;
        target = "/sbin/init";
      }
      {
        source = rootDirs;
        target = "/mnt";
      }
    ];
    format = "qcow2";
    onlyNixStore = false;
    partitionTableType = "efi";
    bootSize = "8M";
    rootGPUID = "fac0aeec-7358-4d5c-a3aa-ba899b14a17f";
    installBootLoader = false;
    touchEFIVars = false;
    diskSize = "auto";
    additionalSpace = "0M";
    copyChannel = false;
    label = "vpsadmin-stage-2";
    name = "stage-2";
    baseName = "stage-2";
  };

in
pkgs.runCommand "managed-vm" { } ''
  mkdir $out
  ln -sf ${kernel}/bzImage $out/kernel
  ln -sf ${stage2Image}/stage-2.qcow2 $out/stage-2
''
