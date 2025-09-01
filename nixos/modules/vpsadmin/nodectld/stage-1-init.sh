#!@shell@

fail() {
    echo $@
    exit 1
}

trap 'fail' 0

echo
echo "[1;32m<<< vpsAdmin Stage 1 >>>[0m"
echo

export PATH=@path@/bin/

echo "Mounting rootfs overlay..."
mount -t tmpfs root /mnt/rootfs -o size=32M || fail "Can't mount root tmpfs"
mkdir -p /mnt/rootfs/rw /mnt/rootfs/workdir

mount --bind / /mnt/image || fail "Failed to mount stage-2 image"

mount -t overlay overlay -o lowerdir=/mnt/image,upperdir=/mnt/rootfs/rw,workdir=/mnt/rootfs/workdir /mnt/overlay

mkdir /mnt/overlay/dev
mount -t devtmpfs devtmpfs /mnt/overlay/dev

exec env -i $(type -P switch_root) /mnt/overlay @bootStage2@ 2> /mnt/overlay/dev/null

echo "Failed to enter stage-2"
exec @shell@
