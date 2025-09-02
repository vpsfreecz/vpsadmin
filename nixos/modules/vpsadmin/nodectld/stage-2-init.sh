#!@shell@

systemConfig=@systemConfig@
export PATH=@path@/bin/

echo
echo -e "\e[1;32m<<< vpsAdmin Stage 2 >>>\e[0m"
echo

mkdir -p /proc /sys /tmp /var/empty /var/log /etc /root /run /nix/var/nix/gcroots
mount -t proc proc /proc
mount -t sysfs sys /sys
# mount -t devtmpfs devtmpfs /dev
# mkdir -p /dev/pts /dev/shm
# mount -t devpts -ogid=3 devpts /dev/pts
# mount -t tmpfs -o mode=1777 tmpfs /tmp
# mount -t tmpfs -o mode=755 tmpfs /run
# mount -t tmpfs tmpfs /dev/shm

ln -sfn /run /var/run
ln -sf /proc/mounts /etc/mtab

touch /run/{u,w}tmp
mkdir /run/lock

hostname @hostName@

$systemConfig/activate

ln -sfn "$systemConfig" /run/booted-system
ln -sfn /run/booted-system /nix/var/nix/gcroots/booted-system

echo "Mounting rootfs"
mkdir -p /mnt/vps

ls -l /dev/disk/by-label
mount -v /dev/disk/by-label/vpsadmin-rootfs /mnt/vps || fail "Unable to mount rootfs"

echo "Starting qemu guest agent"
qemu-ga -d -m virtio-serial

echo "tmp shell"
bash

echo "Starting managed container"
mkdir -p /run/lxc /var/lib/lxc/vps /var/lib/lxc/rootfs /etc/lxc

# TODO: we should also support cgroups v1
mount -t cgroup2 cgroup2 /sys/fs/cgroup
mkdir /sys/fs/cgroup/init
echo $$ > /sys/fs/cgroup/init/cgroup.procs

cat > /var/lib/lxc/vps/config <<'CFG'
lxc.apparmor.profile = unconfined
lxc.uts.name = vps
lxc.rootfs.path = dir:/mnt/vps
lxc.namespace.keep = net user
lxc.autodev = 0
lxc.console.path = /dev/console
lxc.init.cmd = /sbin/init

lxc.mount.auto = proc:rw sys:rw cgroup:rw
lxc.mount.entry = /dev dev none rbind,create=dir 0 0
CFG

echo "Here's out memory"
free -m

lxc-start -F -n vps -P /var/lib/lxc

echo "Managed container exited"
echo "TODO: handle reboot/halt"
