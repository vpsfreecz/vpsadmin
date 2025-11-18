module Transactions::Vps
  class RescueEnter < ::Transaction
    t_name :vps_rescue_enter
    t_type 2037
    queue :vps

    # @param vps [::Vps]
    # @param os_template [::OsTemplate]
    # @param rootfs_mountpoint [String, nil] mountpoint or nil
    def params(vps, os_template, rootfs_mountpoint: nil)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        uuid: vps.uuid.uuid,
        vm_type: vps.vm_type,
        os: vps.os_family.os.name,
        os_family: vps.os_family.name,
        cpu: vps.cpu,
        memory: vps.memory,
        rootfs_volume: {
          id: vps.storage_volume_id,
          pool_path: vps.storage_volume.storage_pool.path,
          name: vps.storage_volume.name,
          format: vps.storage_volume.format,
          label: vps.storage_volume.label
        },
        rescue_volume: {
          id: vps.rescue_volume_id,
          pool_path: vps.rescue_volume.storage_pool.path,
          name: vps.rescue_volume.name,
          format: vps.rescue_volume.format,
          label: vps.rescue_volume.label
        },
        console_port: vps.console_port.port,
        hostname: "rescue-#{vps.id}",
        distribution: os_template.distribution,
        version: os_template.version,
        arch: os_template.arch,
        variant: os_template.variant,
        cgroup_version: vps.cgroup_version_number,
        rescue_rootfs_mountpoint: rootfs_mountpoint
      }
    end
  end
end
