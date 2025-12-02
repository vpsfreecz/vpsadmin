module Transactions::StorageVolume
  class Clone < ::Transaction
    t_name :storage_volume_clone
    t_type 5233
    queue :storage

    def params(src_vol, dst_vol)
      self.vps_id = dst_vol.vps.id
      self.node_id = dst_vol.storage_pool.node_id

      {
        src: {
          storage_pool_uuid: src_vol.storage_pool.uuid.uuid,
          storage_pool_path: src_vol.storage_pool.path,
          name: src_vol.name,
          format: src_vol.format,
          size: src_vol.size
        },
        dst: {
          storage_pool_uuid: dst_vol.storage_pool.uuid.uuid,
          storage_pool_path: dst_vol.storage_pool.path,
          name: dst_vol.name,
          format: dst_vol.format,
          size: dst_vol.size
        }
      }
    end
  end
end
