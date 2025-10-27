module Transactions::StorageVolume
  class Destroy < ::Transaction
    t_name :storage_volume_destroy
    t_type 5232
    queue :storage
    irreversible

    def params(vol)
      self.vps_id = vol.vps.id
      self.node_id = vol.storage_pool.node_id

      {
        storage_pool_uuid: vol.storage_pool.uuid.uuid,
        storage_pool_path: vol.storage_pool.path,
        name: vol.name,
        format: vol.format
      }
    end
  end
end
