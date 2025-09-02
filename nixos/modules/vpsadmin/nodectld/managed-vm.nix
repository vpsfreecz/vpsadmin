{
  config,
  pkgs,
  lib,
}:
let
  kernelModules = [
    "ext4"
    "loop"
    "overlay"
    "tun"
    "virtio"
    "virtio_pci"
    "virtio_net"
    "virtio_rng"
    "virtio_blk"
    "virtio_console"
  ];

  stage2Config = import <nixpkgs/nixos/lib/eval-config.nix> {
    inherit pkgs;

    modules = [
      (
        { config, pkgs, ... }:
        {
          boot.kernelModules = kernelModules;

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

  modules = pkgs.makeModulesClosure {
    rootModules = kernelModules;
    kernel = stage2Config.config.system.modulesTree;
    allowMissing = true;
    firmware = [ ];
  };

  extraUtils =
    pkgs.runCommandCC "extra-utils"
      {
        buildInputs = [
          pkgs.nukeReferences
          pkgs.lvm2
        ];
        allowedReferences = [ "out" ];
      }
      ''
        set +o pipefail
        mkdir -p $out/bin $out/lib
        ln -s $out/bin $out/sbin

        copy_bin_and_libs() {
          [ -f "$out/bin/$(basename $1)" ] && rm "$out/bin/$(basename $1)"
          cp -pd $1 $out/bin
        }

        # Copy Busybox
        for BIN in ${pkgs.busybox}/{s,}bin/*; do
          copy_bin_and_libs $BIN
        done

        # Copy modprobe
        copy_bin_and_libs ${pkgs.kmod}/bin/kmod
        ln -sf kmod $out/bin/modprobe

        # Copy eudev
        copy_bin_and_libs ${udev}/bin/udevd
        copy_bin_and_libs ${udev}/bin/udevadm
        for BIN in ${udev}/lib/udev/*_id; do
          copy_bin_and_libs $BIN
        done

        # Copy ld manually since it isn't detected correctly
        cp -pv ${pkgs.glibc.out}/lib/ld*.so.? $out/lib

        # Copy all of the needed libraries
        find $out/bin $out/lib -type f | while read BIN; do
          echo "Copying libs for executable $BIN"
          LDD="$(ldd $BIN)" || continue
          LIBS="$(echo "$LDD" | awk '{print $3}' | sed '/^$/d')"
          for LIB in $LIBS; do
            TGT="$out/lib/$(basename $LIB)"
            if [ ! -f "$TGT" ]; then
              SRC="$(readlink -e $LIB)"
              cp -pdv "$SRC" "$TGT"
            fi
          done
        done

        # Strip binaries further than normal.
        chmod -R u+w $out
        stripDirs "lib bin" "-s"

        # Run patchelf to make the programs refer to the copied libraries.
        find $out/bin $out/lib -type f | while read i; do
          if ! test -L $i; then
            nuke-refs -e $out $i
          fi
        done

        find $out/bin -type f | while read i; do
          if ! test -L $i; then
            echo "patching $i..."
            patchelf --set-interpreter $out/lib/ld*.so.? --set-rpath $out/lib $i || true
          fi
        done

        # Make sure that the patchelf'ed binaries still work.
        echo "testing patched programs..."
        $out/bin/ash -c 'echo hello world' | grep "hello world"
        export LD_LIBRARY_PATH=$out/lib
        $out/bin/mount --help 2>&1 | grep -q "BusyBox"
      '';
  shell = "${extraUtils}/bin/ash";
  modprobeList = lib.concatStringsSep " " kernelModules;

  udev = pkgs.eudev;
  udevRules = pkgs.runCommand "udev-rules" { allowedReferences = [ extraUtils ]; } ''
    mkdir -p $out

    echo 'ENV{LD_LIBRARY_PATH}="${extraUtils}/lib"' > $out/00-env.rules

    cp -v ${udev}/var/lib/udev/rules.d/60-cdrom_id.rules $out/
    cp -v ${udev}/var/lib/udev/rules.d/60-persistent-storage.rules $out/
    cp -v ${udev}/var/lib/udev/rules.d/80-drivers.rules $out/
    cp -v ${pkgs.lvm2}/lib/udev/rules.d/*.rules $out/

    cat <<'EOF' > $out/90-virtio-ports.rules
    SUBSYSTEM=="virtio-ports", KERNEL=="vport*", ATTR{name}=="?*", SYMLINK+="virtio-ports/$attr{name}"
    EOF

    for i in $out/*.rules; do
        substituteInPlace $i \
          --replace ata_id ${extraUtils}/bin/ata_id \
          --replace scsi_id ${extraUtils}/bin/scsi_id \
          --replace cdrom_id ${extraUtils}/bin/cdrom_id \
          --replace ${pkgs.util-linux}/sbin/blkid ${extraUtils}/bin/blkid \
          --replace /sbin/blkid ${extraUtils}/bin/blkid \
          --replace ${lib.getBin pkgs.lvm2}/bin/dmsetup /bin/dmsetup \
          --replace ${lib.getBin pkgs.lvm2}/bin/lvm /bin/lvm \
          --replace ${pkgs.lvm2}/bin ${extraUtils}/bin \
          --replace ${pkgs.lvm2}/bin ${extraUtils}/bin \
          --replace ${pkgs.bash}/bin/sh ${extraUtils}/bin/sh \
          --replace /usr/bin/readlink ${extraUtils}/bin/readlink \
          --replace /usr/bin/basename ${extraUtils}/bin/basename \
          --replace ${udev}/bin/udevadm ${extraUtils}/bin/udevadm
    done
  '';
  udevHwdb = config.environment.etc."udev/hwdb.bin".source;

  bootStage1 = pkgs.replaceVarsWith {
    src = ./stage-1-init.sh;
    isExecutable = true;
    replacements = {
      inherit
        shell
        modules
        modprobeList
        extraUtils
        udevRules
        udevHwdb
        ;
      bootStage2 = builtins.unsafeDiscardStringContext bootStage2;
    };
  };

  initialRamdisk = pkgs.makeInitrd {
    compressor = "pigz";
    inherit (config.boot.initrd) prepend;

    contents = [
      {
        object = bootStage1;
        symlink = "/init";
      }

      {
        object = config.environment.etc."modprobe.d/nixos.conf".source;
        symlink = "/etc/modprobe.d/nixos.conf";
      }

      {
        object =
          pkgs.runCommand "initrd-kmod-blacklist-ubuntu"
            {
              src = "${pkgs.kmod-blacklist-ubuntu}/modprobe.conf";
              preferLocalBuild = true;
            }
            ''
              target=$out
              ${pkgs.buildPackages.perl}/bin/perl -0pe 's/## file: iwlwifi.conf(.+?)##/##/s;' $src > $out
            '';
        symlink = "/etc/modprobe.d/ubuntu.conf";
      }

      {
        object = pkgs.kmod-debian-aliases;
        symlink = "/etc/modprobe.d/debian.conf";
      }
    ];
  };

  bootStage2 = pkgs.replaceVarsWith {
    src = ./stage-2-init.sh;
    isExecutable = true;
    replacements = {
      shell = "${pkgs.bash}/bin/bash";
      systemConfig = stage2Config.config.system.build.toplevel;
      path = stage2Config.config.system.path;
      inherit (stage2Config.config.networking) hostName;
    };
  };

  # setupRoot = pkgs.runCommand "setup-root" {} ''
  #   mkdir $out
  #   ln -sf ${setupPackages} $out/packages
  #   ln -sf ${config.system.modulesTree} $out/kernel-modules
  # '';

  stage2Image = import <nixpkgs/nixos/lib/make-disk-image.nix> {
    inherit pkgs lib;
    inherit (stage2Config) config;
    additionalPaths = [
      bootStage2
    ];
    # contents = [
    #   { source = setupRoot; target = "/init"; }
    # ];
    format = "qcow2";
    onlyNixStore = false;
    partitionTableType = "none";
    installBootLoader = false;
    touchEFIVars = false;
    diskSize = "auto";
    additionalSpace = "0M";
    copyChannel = false;
    label = "vpsadmin-stage-2";
    name = "stage-2-image";
    baseName = "stage-2";
  };

in
pkgs.runCommand "managed-vm" { } ''
  mkdir $out
  ln -sf ${kernel}/bzImage $out/kernel
  ln -sf ${initialRamdisk}/initrd $out/initrd
  ln -sf ${stage2Image}/stage-2.qcow2 $out/stage-2
''
