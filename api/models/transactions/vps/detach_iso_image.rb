module Transactions::Vps
  class DetachIsoImage < ::Transaction
    t_name :vps_detach_iso_image
    t_type 2042
    queue :vps

    def params(vps, iso_image)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        vps_uuid: vps.uuid.to_s,
        iso_image: {
          pool_path: iso_image.storage_pool.path,
          name: iso_image.name
        }
      }
    end
  end
end
