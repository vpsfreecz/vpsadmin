module Transactions::StorageVolume
  class Format < ::Transaction
    t_name :storage_volume_format
    t_type 5231
    queue :storage

    def params(vol, os_template: nil)
      self.vps_id = vol.vps.id
      self.node_id = vol.storage_pool.node_id

      {
        storage_pool_uuid: vol.storage_pool.uuid.uuid,
        storage_pool_path: vol.storage_pool.path,
        name: vol.name,
        format: vol.format,
        filesystem: vol.filesystem,
        label: vol.label,
        os_template: os_template && {
          distribution: os_template.distribution,
          version: os_template.version,
          arch: os_template.arch,
          variant: os_template.variant,
          vendor: os_template.vendor
        }
      }
    end
  end
end
