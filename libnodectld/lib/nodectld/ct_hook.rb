module NodeCtld
  # Interface for external hook scripts to communicate events to the nodectld
  # daemon.
  module CtHook
    def self.pre_start(pool, ct_id)
      Mounter.prepare_vps_mounts(File.join(pool, 'ct'), ct_id)
    end

    def self.post_mount(pool, ct_id, rootfs_mount)
      Mounter.mount_vps_mounts(File.join(pool, 'ct'), ct_id, rootfs_mount)
    end

    def self.veth_up(ct_id, host_veth, ct_veth)
      RemoteClient.send_or_not(RemoteControl::SOCKET, :ct_hook, {
        hook_name: :veth_up,
        vps_id: ct_id.to_i,
        host_veth: host_veth,
        ct_veth: ct_veth,
      })
    end
  end
end
