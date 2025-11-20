#!@shell@

fail() {
    echo $@
    exit 1
}

mkCgroup() {
    local relPath="$1"
    local subtreeControl="$2"
    local absPath

    case "$cgroupv" in
        1)
            for subsys in /sys/fs/cgroup/* ; do
                absPath="$subsys/$relPath"
                mkdir -p "$absPath"

                if [[ "$subsys" == */cpuset ]] ; then
                    cat "$subsys/cpuset.cpus" > "$absPath/cpuset.cpus"
                    cat "$subsys/cpuset.mems" > "$absPath/cpuset.mems"
                fi
            done
            ;;
        2)
            absPath="/sys/fs/cgroup/$relPath"
            mkdir -p "$absPath"

            if [ "$subtreeControl" == "subtree_control" ] ; then
                for c in `cat /sys/fs/cgroup/cgroup.controllers` ; do
                    echo "+$c" >> "$absPath/cgroup.subtree_control"
                done
            fi
            ;;
    esac
}

setCgroup() {
    local pid="$1"
    local relPath="$2"

    case "$cgroupv" in
        1)
            for subsys in /sys/fs/cgroup/* ; do
                echo $pid > "$subsys/$relPath/cgroup.procs"
            done
            ;;
        2)
            echo $pid > "/sys/fs/cgroup/$relPath/cgroup.procs"
            ;;
    esac
}

runGetty() (
    local console="$1"

    while true ; do
        setsid agetty --autologin root --noclear --keep-baud "$console" 115200,38400,9600 linux
        sleep 1
    done
)

trap 'fail' 0

systemConfig=@systemConfig@
export PATH=@path@/bin/

echo
echo -e "\e[1;32m<<< vpsAdmin Stage 2 >>>\e[0m"
echo

mkdir -p /dev /proc /sys /tmp /var/empty /var/log /etc /root /run /nix/var/nix/gcroots
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs devtmpfs /dev
mkdir -p /dev/pts /dev/shm
mount -t devpts -ogid=3 devpts /dev/pts

ln -sfn /run /var/run
ln -sf /proc/mounts /etc/mtab

action=start
defcgroupv=2
cgroupv=$defcgroupv

for o in $(cat /proc/cmdline); do
    case $o in
        vpsadmin.cgroupv=*)
            set -- $(IFS==; echo $o)
            cgroupv=$2
            ;;
        vpsadmin.distconfig)
            action=distconfig
            ;;
    esac
done

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

if [ -e /dev/disk/by-label/config-2 ] ; then
  echo "Mounting config drive"
  mkdir -p /mnt/config
  mount -o ro /dev/disk/by-label/config-2 /mnt/config
  mkdir -p /run/config/vpsadmin
  [ -d /mnt/config/vpsadmin ] && cp -r /mnt/config/vpsadmin/* /run/config/vpsadmin/
  umount /mnt/config
fi

distconfig rootfs-mount || fail "Unable to mountrootfs"

# CGroups
case "$cgroupv" in
    1) ;;
    2) ;;
    *)
        echo "Invalid cgroup version specified: 'vpsadmin.cgroupv=$cgroupv', " \
                "falling back to v$defcgroupv"
        cgroupv=$defcgroupv
        ;;
esac

case "$cgroupv" in
    1)
        echo "Mounting cgroups in hybrid hierarchy (v1)"
        mount -t tmpfs -o uid=0,gid=0,mode=0755 cgroup /sys/fs/cgroup

        mkdir /sys/fs/cgroup/cpuset
        mount -t cgroup -o cpuset cgroup /sys/fs/cgroup/cpuset

        mkdir /sys/fs/cgroup/cpu,cpuacct
        mount -t cgroup -o cpu,cpuacct cgroup /sys/fs/cgroup/cpu,cpuacct

        mkdir /sys/fs/cgroup/memory
        mount -t cgroup -o memory cgroup /sys/fs/cgroup/memory
        echo 1 > /sys/fs/cgroup/memory/memory.use_hierarchy

        mkdir /sys/fs/cgroup/devices
        mount -t cgroup -o devices cgroup /sys/fs/cgroup/devices

        mkdir /sys/fs/cgroup/freezer
        mount -t cgroup -o freezer cgroup /sys/fs/cgroup/freezer

        mkdir /sys/fs/cgroup/net_cls,net_prio
        mount -t cgroup -o net_cls,net_prio cgroup /sys/fs/cgroup/net_cls,net_prio

        mkdir /sys/fs/cgroup/pids
        mount -t cgroup -o pids cgroup /sys/fs/cgroup/pids

        mkdir /sys/fs/cgroup/perf_event
        mount -t cgroup -o perf_event cgroup /sys/fs/cgroup/perf_event

        mkdir /sys/fs/cgroup/rdma
        mount -t cgroup -o rdma cgroup /sys/fs/cgroup/rdma

        mkdir /sys/fs/cgroup/hugetlb
        mount -t cgroup -o hugetlb cgroup /sys/fs/cgroup/hugetlb

        mkdir /sys/fs/cgroup/systemd
        mount -t cgroup -o name=systemd,none cgroup /sys/fs/cgroup/systemd

        mkdir /sys/fs/cgroup/unified
        mount -t cgroup2 cgroup2 /sys/fs/cgroup/unified
        ;;
    2)
        echo "Mounting cgroups in unified hierarchy (v2)"
        mount -t cgroup2 cgroup2 /sys/fs/cgroup

        for c in `cat /sys/fs/cgroup/cgroup.controllers` ; do
            echo "+$c" >> /sys/fs/cgroup/cgroup.subtree_control
        done
        ;;
esac

mkCgroup init
setCgroup $$ init

echo "Configuring managed container"
distconfig lxc-setup @ctstartmenu@

mkdir -p /run/lxc /var/lib/lxc/vps /var/lib/lxc/rootfs /etc/lxc

echo "Starting qemu guest agent"
qemu-ga-runner.sh &
qemuGaPid=$!

echo "Starting management consoles"
runGetty hvc1 &
runGetty hvc2 &

if [ "$action" == "distconfig" ] ; then
    echo "Entering distconfig mode"
    sleep 3600

    echo "Syncing filesystems"
    sync

    echo "Halting"
    echo o > /proc/sysrq-trigger
    sleep 60
    exit 0
fi

echo "tmp shell"
bash

echo "Starting managed container"
distconfig start
setCgroup $$ /

lxc-start -F -n vps -P /var/lib/lxc &
lxcPid=$!

# It is necessary to wait for LXC to start before switching cgroups
# back to init
for _ in {1..600} ; do
    [ -f /run/lxc-started ] && break
    sleep 0.1
done

if [ ! -f /run/lxc-started ] ; then
    fail "LXC not started"
fi

rm -f /run/lxc-started

echo -1000 > /proc/$$/oom_score_adj
setCgroup $$ init

wait $lxcPid
lxcStatus=$?

echo "Managed container exited with $lxcStatus"

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

