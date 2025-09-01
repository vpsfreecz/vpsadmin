#! @shell@

console=console

fail() {
    if [ -n "$panicOnFail" ]; then exit 1; fi

    # If starting stage 1 failed, allow the user to repair the problem
    # in an interactive shell.
    cat <<EOF

Error: [1;31m ${1} [0m

An error occurred in stage 1 of the boot process. Press one of the following
keys:

  i) to launch an interactive shell
  r) to reboot immediately
  *) to ignore the error and continue
EOF

    read reply

    if [ "$reply" = i ]; then
        echo "Starting interactive shell..."
        setsid @shell@ -c "@shell@ < /dev/$console >/dev/$console 2>/dev/$console" || fail "Can't spawn shell"
    elif [ "$reply" = r ]; then
        echo "Rebooting..."
        reboot -f
    else
        echo "Continuing..."
    fi
}

trap 'fail' 0

echo
echo "[1;32m<<< vpsAdmin VPS >>>[0m"
echo

export LD_LIBRARY_PATH=@extraUtils@/lib
export PATH=@extraUtils@/bin/
ln -s @extraUtils@/bin /bin
# hardcoded in util-linux's mount helper search path `/run/wrappers/bin:/run/current-system/sw/bin:/sbin`
ln -s @extraUtils@/bin /sbin

mkdir -p /proc /sys /dev /etc/udev /tmp /run/ /lib/ /mnt/ /var/log

mount -t devtmpfs devtmpfs /dev/
mkdir /dev/pts
mount -t devpts devpts /dev/pts

mount -t proc proc /proc
mount -t sysfs sysfs /sys

ln -s @modules@/lib/modules /lib/modules

echo @extraUtils@/bin/modprobe > /proc/sys/kernel/modprobe
for x in @modprobeList@; do
  modprobe -b $x
done

echo "running udev..."
mkdir -p /etc/udev
ln -sfn @udevRules@ /etc/udev/rules.d
ln -sfn @udevHwdb@ /etc/udev/hwdb.bin
udevd --daemon --resolve-names=never
udevadm trigger --action=add
udevadm settle --timeout=30 || fail "udevadm settle timed-out"
udevadm control --exit

echo "Mounting rootfs"
mkdir -p /mnt/vps
mount -v /dev/vda /mnt/vps || fail "Unable to mount rootfs"

echo "Starting managed container"
mkdir -p /run/lxc /var/lib/lxc/vps /var/lib/lxc/rootfs /etc/lxc

# TODO: we could also support cgroups v1
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
