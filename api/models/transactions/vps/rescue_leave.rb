module Transactions::Vps
  class RescueLeave < ::Transaction
    t_name :vps_rescue_leave
    t_type 2038
    queue :vps
    irreversible

    # @param vps [::Vps]
    def params(vps)
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
        console_port: vps.console_port.port,
        hostname: vps.manage_hostname ? vps.hostname : nil,
        distribution: vps.os_template.distribution,
        version: vps.os_template.version,
        cgroup_version: vps.cgroup_version_number
      }
    end
  end
end
