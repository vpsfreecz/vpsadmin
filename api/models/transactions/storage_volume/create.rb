module Transactions::StorageVolume
  class Create < ::Transaction
    t_name :storage_volume_create
    t_type 5230
    queue :storage

    def params(vol)
      self.vps_id = vol.vps.id
      self.node_id = vol.storage_pool.node_id

      {
        storage_pool_uuid: vol.storage_pool.uuid.uuid,
        storage_pool_path: vol.storage_pool.path,
        name: vol.name,
        format: vol.format,
        size: vol.size
      }
    end
  end
end
