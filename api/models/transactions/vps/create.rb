module Transactions::Vps
  class Create < ::Transaction
    t_name :vps_create
    t_type 3001
    queue :vps

    # @param vps [::Vps]
    # @param [Boolean] empty do not apply any template
    def params(vps, empty: false)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      if vps.container?
        {
          pool_name: vps.dataset_in_pool.pool.name,
          pool_fs: vps.dataset_in_pool.pool.filesystem,
          dataset_name: vps.dataset_in_pool.dataset.full_name,
          userns_map: vps.user_namespace_map_id.to_s,
          map_mode: vps.map_mode,
          hostname: vps.manage_hostname ? vps.hostname : nil,
          distribution: vps.os_template.distribution,
          version: vps.os_template.version,
          arch: vps.os_template.arch,
          vendor: vps.os_template.vendor,
          variant: vps.os_template.variant,
          empty:
        }
      else
        {
          uuid: vps.uuid.uuid,
          vm_type: vps.vm_type,
          os: vps.os_family.os.name,
          os_family: vps.os_family.name,
          rootfs_label: vps.storage_volume.label,
          console_port: vps.console_port&.port,
          hostname: vps.manage_hostname ? vps.hostname : nil,
          distribution: vps.os_template&.distribution,
          version: vps.os_template&.version,
          arch: vps.os_template&.arch,
          variant: vps.os_template&.variant
        }
      end
    end
  end
end
