module Transactions::Vps
  class Reinstall < ::Transaction
    t_name :vps_reinstall
    t_type 3003
    queue :vps

    def params(vps, template)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      if vps.container?
        {
          pool_name: vps.dataset_in_pool.pool.name,
          pool_fs: vps.dataset_in_pool.pool.filesystem,
          distribution: template.distribution,
          version: template.version,
          arch: template.arch,
          vendor: template.vendor,
          variant: template.variant
        }
      else
        {
          uuid: vps.uuid.uuid,
          vm_type: vps.vm_type,
          cpu: vps.cpu,
          memory: vps.memory,
          rootfs_volume: {
            pool_path: vps.storage_volume.storage_pool.path,
            name: vps.storage_volume.name,
            format: vps.storage_volume.format,
            label: vps.storage_volume.label
          },
          console_port: vps.console_port.port,
          distribution: template.distribution,
          version: template.version,
          arch: template.arch,
          variant: template.variant,
          cgroup_version: vps.cgroup_version_number
        }
      end
    end
  end
end
