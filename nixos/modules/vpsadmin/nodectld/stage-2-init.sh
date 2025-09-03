#!@shell@

fail() {
    echo $@
    exit 1
}

trap 'fail' 0

systemConfig=@systemConfig@
export PATH=@path@/bin/

echo
echo -e "\e[1;32m<<< vpsAdmin Stage 2 >>>\e[0m"
echo

mkdir -p /proc /sys /tmp /var/empty /var/log /etc /root /run /nix/var/nix/gcroots
mount -t proc proc /proc
mount -t sysfs sys /sys
mkdir -p /dev/pts /dev/shm
mount -t devpts -ogid=3 devpts /dev/pts

ln -sfn /run /var/run
ln -sf /proc/mounts /etc/mtab

touch /run/{u,w}tmp
mkdir /run/lock

hostname @hostName@

$systemConfig/activate

ln -sfn "$systemConfig" /run/booted-system
ln -sfn /run/booted-system /nix/var/nix/gcroots/booted-system

echo "Running udev..."
mkdir -p /etc/udev
ln -sfn @udevRules@ /etc/udev/rules.d
ln -sfn @udevHwdb@ /etc/udev/hwdb.bin
@udev@/bin/udevd --daemon --resolve-names=never
@udev@/bin/udevadm trigger --action=add
@udev@/bin/udevadm settle --timeout=30 || fail "udevadm settle timed-out"
@udev@/bin/udevadm control --exit

echo "Mounting container rootfs"
mkdir -p /mnt/vps
mount -v /dev/disk/by-label/vpsadmin-rootfs /mnt/vps || fail "Unable to mount rootfs"

# TODO: we should also support cgroups v1
echo "Mounting cgroups"
mount -t cgroup2 cgroup2 /sys/fs/cgroup
mkdir /sys/fs/cgroup/init
echo $$ > /sys/fs/cgroup/init/cgroup.procs

echo "Starting qemu guest agent"
qemu-ga -d -m virtio-serial

echo "tmp shell"
bash

echo "Starting managed container"
mkdir -p /run/lxc /var/lib/lxc/vps /var/lib/lxc/rootfs /etc/lxc

lxc-start -F -n vps -P /var/lib/lxc

echo "Managed container exited"

echo "Syncing filesystems..."
sync

if [ -e /run/lxc-target ] ; then
    target="$(cat /run/lxc-target)"

    case "$target" in
    reboot)
        echo "Rebooting..."
        sleep 1
        echo b > /proc/sysrq-trigger
        ;;
    *)
        echo "Halting..."
        sleep 1
        echo o > /proc/sysrq-trigger
        ;;
    esac
else
    echo "Unable to determine reboot/halt request, rebooting..."
    sleep 1
    echo b > /proc/sysrq-trigger
fi

# Avoid exiting to avoid kernel panic (we are init)
sleep 60

