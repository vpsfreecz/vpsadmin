{
  config,
  pkgs,
  lib,
}:
let
  stage2Config = import <nixpkgs/nixos/lib/eval-config.nix> {
    inherit pkgs;

    modules = [
      (
        { config, pkgs, ... }:
        {
          boot.kernelPackages = pkgs.linuxPackagesFor (
            pkgs.linuxPackages.kernel.override {
              structuredExtraConfig = with lib.kernel; {
                EXT4_FS = yes;

                HW_RANDOM = yes;
                HW_RANDOM_VIRTIO = yes;

                OVERLAY_FS = yes;

                VIRTIO = yes;
                VIRTIO_BLK = yes;
                VIRTIO_CONSOLE = yes;
                VIRTIO_NET = yes;
                VIRTIO_PCI = yes;
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
            lxc
            qemu
          ];

          networking.hostName = "stage-2";

          documentation = {
            enable = false;
            dev.enable = false;
            info.enable = false;
            man.enable = false;
            nixos.enable = false;
          };

          fonts.fontconfig.enable = false;
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
    };
  };

  rootDirs = pkgs.runCommand "root-dirs" { } ''
    mkdir $out
    cd $out
    mkdir rootfs image overlay
  '';

  bootImage = import <nixpkgs/nixos/lib/make-disk-image.nix> {
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
    partitionTableType = "none";
    installBootLoader = false;
    touchEFIVars = false;
    diskSize = "auto";
    additionalSpace = "0M";
    copyChannel = false;
    label = "vpsadmin-boot";
    name = "boot-image";
    baseName = "disk";
  };

in
pkgs.runCommand "managed-vm" { } ''
  mkdir $out
  ln -sf ${kernel}/bzImage $out/kernel
  ln -sf ${bootImage}/disk.qcow2 $out/disk
''
