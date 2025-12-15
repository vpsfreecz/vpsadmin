module Transactions::Vps
  class AttachIsoImage < ::Transaction
    t_name :vps_attach_iso_image
    t_type 2041
    queue :vps

    def params(vps, iso_image)
      self.vps_id = vps.id
      self.node_id = vps.node_id

      {
        vps_uuid: vps.uuid.to_s,
        new_iso_image: {
          pool_path: iso_image.storage_pool.path,
          name: iso_image.name
        },
        original_iso_image: vps.iso_image && {
          pool_path: vps.iso_image.storage_pool.path,
          name: vps.iso_image.name
        }
      }
    end
  end
end
