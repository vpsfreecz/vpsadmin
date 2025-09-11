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
            configureCt
            distconfig
            jq
            lxc
            qemu
            qemuGaRunner
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

  configureCt = pkgs.replaceVarsWith {
    src = ./configure-ct.rb;
    dir = "bin";
    isExecutable = true;
    replacements = {
      inherit (pkgs) ctstartmenu ruby;
      inherit lxcConfig;
    };
  };

  lxcConfig = pkgs.writeText "lxc-config.erb" ''
    lxc.apparmor.profile = unconfined
    lxc.uts.name = vps
    lxc.rootfs.path = dir:/mnt/vps
    lxc.namespace.keep = net user
    lxc.autodev = 0
    lxc.console.path = /dev/console
    lxc.pty.max = 4096
    lxc.tty.max = 64
    lxc.init.cmd = <%= init_cmd %>

    lxc.mount.auto = proc:rw sys:rw cgroup:rw
    lxc.mount.entry = /dev dev none rbind,create=dir 0 0

    lxc.hook.pre-start = ${preStartHook}
    lxc.hook.post-stop = ${postStopHook}
  '';

  preStartHook = pkgs.writeScript "pre-start.sh" ''
    #!${pkgs.bash}/bin/bash

    touch /run/lxc-started
    exit 0
  '';

  postStopHook = pkgs.writeScript "post-stop.sh" ''
    #!${pkgs.bash}/bin/bash

    [ -z "$LXC_TARGET" ] && LXC_TARGET=unknown

    echo "$LXC_TARGET" > /run/lxc-target
    exit 0
  '';

  bootImage = import <nixpkgs/nixos/lib/make-disk-image.nix> {
    inherit pkgs lib;
    inherit (stage2Config) config;
    additionalPaths = [
      bootStage2
      lxcConfig
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
